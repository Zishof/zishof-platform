import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';

/// Fase sinkronisasi utk indikator UI (lihat IndikatorSinkronMaster).
enum FaseSinkron { diam, adaAntrean, mengirim, baruTersinkron, adaGagal }

/// Snapshot status sinkron master -- immutable supaya ValueNotifier terpicu.
class StatusSinkronMaster {
  final FaseSinkron fase;
  final int antrean;
  final int gagal;
  const StatusSinkronMaster(this.fase, this.antrean, this.gagal);

  @override
  bool operator ==(Object other) =>
      other is StatusSinkronMaster &&
      other.fase == fase &&
      other.antrean == antrean &&
      other.gagal == gagal;

  @override
  int get hashCode => Object.hash(fase, antrean, gagal);
}

/// <h3>Offline-first CRUD data MASTER (anggota, produk, jenis produk, dst).</h3>
///
/// Pola: [simpanAtauAntre] MENCOBA server dulu; bila kegagalan MURNI jaringan
/// ([ApiException.offline]) mutasi diantre di tabel `outbox_master` (core_db
/// v10, coalesce per [kunci] -- edit berulang baris yang sama saat offline
/// hanya menyisakan payload terakhir) lalu dikirim ulang di latar oleh
/// [flush] (timer periodik + segera setelah antre). Penolakan BISNIS server
/// tidak pernah diantre -- dilempar lagi supaya user membaca pesannya.
///
/// Sisi baca: [daftarDenganCache] menyimpan snapshot daftar ke
/// `cache_referensi` setiap fetch sukses dan menyajikannya kembali saat
/// offline; [terapkanLokal] meng-update snapshot itu optimistis begitu ada
/// mutasi offline sehingga user langsung melihat hasil editnya di tabel.
///
/// [status] (ValueNotifier) menggerakkan indikator animasi: badge antrean ->
/// ikon berputar saat kirim -> centang "tersinkron" sesaat setelah sukses.
///
/// CATATAN duplikasi: replay `*_simpan` ber-`id` idempoten (update). Create
/// baru mengandalkan penolakan duplikat-nama di server (pola master AIS);
/// baris antrean yang ditolak ditandai GAGAL permanen dan tampil di badge.
/// Status satu BARIS master utk indikator per-baris di tabel
/// (lihat IndikatorBarisSinkron).
enum StatusBarisSinkron { menunggu, gagal, baruTersinkron }

class MasterOffline {
  MasterOffline._();

  static final ValueNotifier<StatusSinkronMaster> status =
      ValueNotifier<StatusSinkronMaster>(
          const StatusSinkronMaster(FaseSinkron.diam, 0, 0));

  /// Berubah setiap ada pergeseran status per-baris (antre/sukses/gagal) --
  /// murah didengarkan oleh banyak baris tabel sekaligus.
  static final ValueNotifier<int> revisiBaris = ValueNotifier<int>(0);

  // kunci -> PENDING | GAGAL (cermin outbox; dihidrasi ulang dari DB).
  static final Map<String, String> _statusBaris = <String, String>{};
  // kunci yang BARU SAJA terbukti sampai server -> centang animasi sesaat.
  static final Set<String> _barisBaruSukses = <String>{};
  static final Map<String, Timer> _timerHapusSukses = <String, Timer>{};

  /// Lama centang per-baris tampil sebelum memudar.
  static const Duration durasiCentangBaris = Duration(seconds: 4);

  static Timer? _timer;
  static bool _sedangFlush = false;
  static Timer? _timerKembaliDiam;

  /// Status baris utk [kunci] ('entitas:id' / '_kunci' pada baris cache),
  /// null bila baris tidak sedang antre/gagal/baru-tersinkron.
  static StatusBarisSinkron? statusBaris(String kunci) {
    if (_barisBaruSukses.contains(kunci)) {
      return StatusBarisSinkron.baruTersinkron;
    }
    switch (_statusBaris[kunci]) {
      case 'PENDING':
        return StatusBarisSinkron.menunggu;
      case 'GAGAL':
        return StatusBarisSinkron.gagal;
    }
    return null;
  }

  static void _tandaiBarisMenunggu(String? kunci) {
    if (kunci == null) return;
    _statusBaris[kunci] = 'PENDING';
    revisiBaris.value++;
  }

  static void _tandaiBarisGagal(String? kunci) {
    if (kunci == null) return;
    _statusBaris[kunci] = 'GAGAL';
    revisiBaris.value++;
  }

  static void _tandaiBarisSukses(String? kunci) {
    if (kunci == null) return;
    _statusBaris.remove(kunci);
    _barisBaruSukses.add(kunci);
    revisiBaris.value++;
    _timerHapusSukses[kunci]?.cancel();
    _timerHapusSukses[kunci] = Timer(durasiCentangBaris, () {
      _barisBaruSukses.remove(kunci);
      _timerHapusSukses.remove(kunci);
      revisiBaris.value++;
    });
  }

  /// Utk widget test: suntik status baris tanpa DB/jaringan.
  @visibleForTesting
  static void aturStatusBarisUntukTest(String kunci, String? status,
      {bool baruSukses = false}) {
    if (status == null) {
      _statusBaris.remove(kunci);
    } else {
      _statusBaris[kunci] = status;
    }
    if (baruSukses) {
      _barisBaruSukses.add(kunci);
    } else {
      _barisBaruSukses.remove(kunci);
    }
    revisiBaris.value++;
  }

  /// Interval retry latar (permintaan bisnis: +-5 menit sekali). Publik agar
  /// test bisa memeriksa kontraknya. Timer BERHENTI otomatis saat antrean
  /// kosong (lihat _muatUlangHitungan) dan hidup lagi begitu ada yang antre.
  static const Duration intervalFlush = Duration(minutes: 5);

  /// Mulai flush periodik (idempoten; dipanggil dari indikator/layar mana pun).
  static void pastikanTimer() {
    _timer ??= Timer.periodic(intervalFlush, (_) => flush());
    _muatUlangHitungan();
  }

  /// Hentikan timer (utk test / logout).
  @visibleForTesting
  static void hentikanTimer() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _muatUlangHitungan({FaseSinkron? paksaFase}) async {
    final pending = await CoreDb.instance.outboxMasterPending();
    final gagalRows = await CoreDb.instance.outboxMasterGagal(batas: 500);
    final antrean = pending.length;
    final gagal = gagalRows.length;
    final fase = paksaFase ??
        (antrean > 0
            ? FaseSinkron.adaAntrean
            : gagal > 0
                ? FaseSinkron.adaGagal
                : FaseSinkron.diam);
    status.value = StatusSinkronMaster(fase, antrean, gagal);
    // Antrean kosong = tidak ada yang perlu dikirim ulang -> hentikan timer
    // (pengecekan berhenti otomatis; hidup lagi lewat pastikanTimer saat ada
    // mutasi baru yang diantre atau layar master dibuka).
    if (antrean == 0 && paksaFase == null) {
      _timer?.cancel();
      _timer = null;
    }
    // Hidrasi status per-baris dari DB (bertahan melewati restart aplikasi).
    final baru = <String, String>{
      for (final r in pending)
        if (r['kunci'] != null) '${r['kunci']}': 'PENDING',
      for (final r in gagalRows)
        if (r['kunci'] != null) '${r['kunci']}': 'GAGAL',
    };
    if (!mapEquals(baru, _statusBaris)) {
      _statusBaris
        ..clear()
        ..addAll(baru);
      revisiBaris.value++;
    }
  }

  /// Simpan/hapus master: server dulu; offline -> antre + `{offline: true}`.
  ///
  /// [kunci] identitas baris utk coalesce, mis. `'produk:123'` (edit) atau
  /// `'produk:baru:<stempel>'` (create -- unik per draf). [cacheKey] +
  /// [rowLokal] opsional: bila offline, baris diterapkan optimistis ke
  /// snapshot daftar sehingga tabel langsung memperlihatkan perubahan;
  /// [hapusLokal] true berarti baris dihapus dari snapshot (utk aksi hapus,
  /// cocokkan lewat kolom 'id' di [rowLokal]).
  static Future<Map<String, dynamic>> simpanAtauAntre(
    String aksi,
    Map<String, dynamic> body, {
    String? kunci,
    String? cacheKey,
    Map<String, dynamic>? rowLokal,
    bool hapusLokal = false,
  }) async {
    pastikanTimer();
    try {
      final hasil = await ApiClient.instance.aksi(aksi, body);
      // Baris ini TERBUKTI sampai server -> centang animasi per-baris.
      _tandaiBarisSukses(kunci);
      // Kesempatan bagus utk mengosongkan antrean lama begitu server terbukti
      // terjangkau -- tanpa menunggu tick timer berikutnya.
      unawaited(flush());
      return hasil;
    } on ApiException catch (e) {
      if (!e.offline) rethrow; // penolakan bisnis -> user harus melihatnya.
      // Bekal dedup replay: server yang sudah mendukung boleh mengabaikan
      // kiriman ulang ber-id sama (field asing aman utk server lama).
      final antreBody = <String, dynamic>{
        ...body,
        'client_mutation_id':
            '${kunci ?? aksi}:${DateTime.now().microsecondsSinceEpoch}',
      };
      await CoreDb.instance
          .outboxMasterTambah(aksi, kunci, jsonEncode(antreBody));
      if (cacheKey != null && rowLokal != null) {
        await terapkanLokal(cacheKey, rowLokal,
            hapus: hapusLokal, kunci: kunci);
      }
      _tandaiBarisMenunggu(kunci);
      await _muatUlangHitungan();
      return {'status': 'success', 'offline': true};
    }
  }

  /// LANGKAH 1 alur "simpan lokal dulu" (dialog TombolSimpan/prosesSimpan):
  /// tulis mutasi ke antrean + terapkan optimistis ke snapshot daftar, TANPA
  /// menyentuh jaringan. Return id baris antrean utk [kirimSatuAntrean].
  static Future<int> antreLokal(
    String aksi,
    Map<String, dynamic> body, {
    String? kunci,
    String? cacheKey,
    Map<String, dynamic>? rowLokal,
    bool hapusLokal = false,
  }) async {
    pastikanTimer();
    final antreBody = <String, dynamic>{
      ...body,
      'client_mutation_id':
          '${kunci ?? aksi}:${DateTime.now().microsecondsSinceEpoch}',
    };
    final id = await CoreDb.instance
        .outboxMasterTambah(aksi, kunci, jsonEncode(antreBody));
    if (cacheKey != null && rowLokal != null) {
      await terapkanLokal(cacheKey, rowLokal, hapus: hapusLokal, kunci: kunci);
    }
    _tandaiBarisMenunggu(kunci);
    await _muatUlangHitungan();
    return id;
  }

  /// LANGKAH 2 alur "simpan lokal dulu": coba kirim SATU baris antrean itu
  /// segera. Sukses -> baris ditandai SYNCED + centang per-baris, return
  /// respons server. Offline -> percobaan dicatat, lempar ulang (baris tetap
  /// antre; pemanggil menutup jendela). Penolakan BISNIS -> baris antrean
  /// DIHAPUS (user melihat pesannya langsung di form) lalu dilempar ulang.
  static Future<Map<String, dynamic>> kirimSatuAntrean(
      int idAntrean, String aksi, Map<String, dynamic> body,
      {String? kunci}) async {
    try {
      final hasil = await ApiClient.instance.aksi(aksi, body);
      await CoreDb.instance.outboxMasterTandaiSukses(idAntrean);
      _tandaiBarisSukses(kunci);
      await _muatUlangHitungan();
      // Server terbukti terjangkau -- sekalian kosongkan antrean lama.
      unawaited(flush());
      return hasil;
    } on ApiException catch (e) {
      if (e.offline) {
        await CoreDb.instance.outboxMasterCatatPercobaan(idAntrean, e.pesan);
        await _muatUlangHitungan();
        rethrow;
      }
      await CoreDb.instance.outboxMasterHapus(idAntrean);
      if (kunci != null) {
        _statusBaris.remove(kunci);
        revisiBaris.value++;
      }
      await _muatUlangHitungan();
      rethrow;
    }
  }

  /// GENERIK semua modul CRUD: apakah cache daftar [cacheKey] masih kosong --
  /// pemicu sinkron awal ber-progress (lihat [hidrasiAwal] +
  /// widgets/progress_sinkron_awal.dart).
  static Future<bool> perluSinkronAwal(String cacheKey) async {
    return !(await CoreDb.instance.adaCacheReferensiList(cacheKey));
  }

  /// GENERIK: jumlah baris cache daftar lokal (0 bila belum ada).
  static Future<int> jumlahCacheLokal(String cacheKey) {
    return CoreDb.instance.jumlahCacheReferensiList(cacheKey);
  }

  /// GENERIK semua modul CRUD: HIDRASI AWAL -- unduh SELURUH daftar dari aksi
  /// list ber-halaman dan simpan utuh ke cache lokal [cacheKey]. [lapor]
  /// dipanggil per halaman (tersinkron, total-bila-diketahui) utk progress
  /// bar; pasangkan dgn `jalankanDenganProgressSinkron` di widget. Return
  /// jumlah baris tersinkron. Kegagalan di tengah: halaman yang SUDAH
  /// terunduh tetap disimpan sebelum error diteruskan (sinkron ulang aman,
  /// replace penuh).
  static Future<int> hidrasiAwal(
    String aksi,
    Map<String, dynamic> bodyDasar,
    String cacheKey, {
    String fieldData = 'data',
    int pageSize = 500,
    String paramPage = 'page',
    String paramPageSize = 'page_size',
    int maksBaris = 100000,
    void Function(int tersinkron, int? total)? lapor,
  }) async {
    final semua = <dynamic>[];
    var page = 1;
    int? total;
    try {
      while (semua.length < maksBaris) {
        final hasil = await ApiClient.instance.aksi(aksi, {
          ...bodyDasar,
          paramPage: page,
          paramPageSize: pageSize,
        });
        final data = (hasil[fieldData] as List?) ?? const [];
        semua.addAll(data);
        total = total ?? (hasil['total'] as num?)?.toInt();
        if (lapor != null) lapor(semua.length, total);
        final habis = data.length < pageSize ||
            (total != null && semua.length >= total);
        if (habis) break;
        page++;
      }
    } catch (e) {
      if (semua.isNotEmpty) {
        await CoreDb.instance.simpanCacheReferensi(cacheKey, jsonEncode(semua));
      }
      rethrow;
    }
    await CoreDb.instance.simpanCacheReferensi(cacheKey, jsonEncode(semua));
    return semua.length;
  }

  /// Hasil satu emisi [daftarCacheDulu]: data + asal + diff vs tampilan lama.
  /// [idBaru]/[idBerubah] dipakai layar utk animasi kilau baris; [jumlahHapus]
  /// utk banner "N data dihapus dari server" (barisnya sudah lenyap dari list).
  /// Kunci diff = kolom 'id' (fallback '_kunci' utk draf offline).
  static Map<String, dynamic> _hasilDaftar(List data,
      {required bool dariServer,
      Set<String>? idBaru,
      Set<String>? idBerubah,
      int jumlahHapus = 0,
      String fieldData = 'data',
      int? total}) {
    return {
      'status': '00',
      fieldData: data,
      'dariServer': dariServer,
      if (!dariServer) 'offline': true,
      // total server WAJIB diteruskan -- tanpanya layar jatuh ke data.length
      // (satu halaman) dan paginasi macet di "Halaman 1/1".
      if (total != null) 'total': total,
      'idBaru': idBaru ?? const <String>{},
      'idBerubah': idBerubah ?? const <String>{},
      'jumlahHapus': jumlahHapus,
    };
  }

  static String? _kunciDiff(dynamic e) {
    if (e is! Map) return null;
    final id = e['id'];
    if (id != null) return '$id';
    final k = e['_kunci'];
    return k == null ? null : '$k';
  }

  /// <h3>Muat daftar LOKAL DULU, lalu server di latar (permintaan bisnis).</h3>
  ///
  /// Emisi lewat [onData] (bisa dipanggil 1-2 kali):
  /// 1. Snapshot lokal seketika (bila ada) -- layar langsung render tanpa
  ///    menunggu jaringan.
  /// 2. Hasil server saat tiba, DIGABUNG (merge/upsert per baris) ke cache
  ///    lokal -- DATA LOKAL TIDAK PERNAH DIHAPUS oleh respons parsial
  ///    (halaman/pencarian): baris yang dikirim server = otoritatif
  ///    (diperbarui), baris yang tidak dikirim = tetap dipertahankan lokal.
  ///    Diff ('idBaru'/'idBerubah'/'jumlahHapus') disertakan utk animasi --
  ///    termasuk perubahan dari kasir LAIN.
  ///
  /// [responsLengkap] true HANYA utk aksi yang mengembalikan SELURUH daftar
  /// (tanpa paginasi/filter): barulah baris lokal yang tak ada di respons
  /// boleh dianggap benar-benar terhapus di server (di-drop + dihitung di
  /// 'jumlahHapus'). Default false = merge murni tanpa penghapusan.
  ///
  /// Saat offline hanya emisi (1) yang terjadi (tanpa error); bila belum ada
  /// cache sama sekali dan server tak terjangkau, ApiException diteruskan.
  static Future<void> daftarCacheDulu(
    String aksi,
    Map<String, dynamic> body,
    String cacheKey, {
    required void Function(Map<String, dynamic> hasil) onData,
    String fieldData = 'data',
    bool responsLengkap = false,
  }) async {
    pastikanTimer();
    List? lokal;
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
    if (tersimpan != null) {
      try {
        lokal = jsonDecode(tersimpan) as List;
        onData(_hasilDaftar(lokal,
            dariServer: false, fieldData: fieldData));
      } catch (_) {
        lokal = null; // cache rusak -- lanjut jalur server biasa.
      }
    }
    try {
      final hasil = await ApiClient.instance.aksi(aksi, body);
      final data = hasil[fieldData];
      if (data is List) {
        // Diff vs isi lokal: baru, berubah isi, dan (bila respons lengkap)
        // hilang. Kunci = id / _kunci draf offline.
        final petaLama = <String, String>{};
        final barisLama = <String, dynamic>{};
        for (final e in (lokal ?? const [])) {
          final k = _kunciDiff(e);
          if (k != null) {
            petaLama[k] = jsonEncode(e);
            barisLama[k] = e;
          }
        }
        // PAGAR 1: baris lokal yang masih ANTRE/GAGAL kirim (punya _kunci di
        // peta status) per definisi LEBIH BARU daripada salinan server --
        // jangan ditimpa, jangan dihitung terhapus.
        final kunciDilindungi = <String>{
          for (final entri in barisLama.entries)
            if (entri.value is Map &&
                (entri.value as Map)['_kunci'] is String &&
                _statusBaris
                    .containsKey((entri.value as Map)['_kunci'] as String))
              entri.key,
        };
        final idBaru = <String>{};
        final idBerubah = <String>{};
        final kunciServer = <String>{};
        for (final e in data) {
          final k = _kunciDiff(e);
          if (k == null) continue;
          kunciServer.add(k);
          final lama = petaLama[k];
          if (lama == null) {
            if (lokal != null) idBaru.add(k); // emisi pertama tak perlu kilau.
          } else if (lama != jsonEncode(e) && !kunciDilindungi.contains(k)) {
            idBerubah.add(k);
          }
        }
        // PAGAR 2: penghapusan hanya boleh disimpulkan dari respons yang
        // BENAR-BENAR memuat seluruh daftar: dinyatakan lengkap oleh caller
        // DAN tanpa filter kata kunci DAN jumlah baris mencakup total server
        // (bila server mengirim total). Respons berhalaman/terfilter TIDAK
        // PERNAH menghapus data lokal (akar insiden "41 dihapus" 2026-08-19).
        final kataKunci = '${body['keyword'] ?? body['q'] ?? ''}'.trim();
        final totalServer = (hasil['total'] as num?)?.toInt();
        final benarLengkap = responsLengkap &&
            kataKunci.isEmpty &&
            (totalServer == null || data.length >= totalServer);
        var jumlahHapus = 0;
        List gabungan;
        if (benarLengkap) {
          // Replace: yang hilang memang terhapus di server -- kecuali baris
          // terlindungi, yang tetap dipertahankan (dan dipakai menggantikan
          // salinan server yang lebih lama utk id yang sama).
          final tertahan = <dynamic>[
            for (final k in kunciDilindungi)
              if (!kunciServer.contains(k)) barisLama[k],
          ];
          gabungan = [
            ...tertahan,
            for (final e in data)
              kunciDilindungi.contains(_kunciDiff(e) ?? '')
                  ? barisLama[_kunciDiff(e)]
                  : e,
          ];
          if (lokal != null) {
            jumlahHapus = petaLama.keys
                .where((k) =>
                    !kunciServer.contains(k) && !kunciDilindungi.contains(k))
                .length;
          }
        } else {
          // MERGE: baris server menimpa versi lokalnya (kecuali terlindungi);
          // baris lokal di luar cakupan respons (halaman/filter lain)
          // DIPERTAHANKAN.
          final petaGabung = <String, dynamic>{};
          var tanpaKunci = 0;
          for (final e in (lokal ?? const [])) {
            final k = _kunciDiff(e);
            if (k != null) {
              petaGabung[k] = e;
            } else {
              petaGabung['~tanpa-kunci-${tanpaKunci++}'] = e;
            }
          }
          for (final e in data) {
            final k = _kunciDiff(e);
            if (k != null) {
              if (!kunciDilindungi.contains(k)) petaGabung[k] = e;
            } else {
              petaGabung['~tanpa-kunci-${tanpaKunci++}'] = e;
            }
          }
          gabungan = petaGabung.values.toList();
        }
        await CoreDb.instance
            .simpanCacheReferensi(cacheKey, jsonEncode(gabungan));
        // Yang ditampilkan pun memakai versi lokal utk baris terlindungi.
        final tampil = [
          for (final e in data)
            kunciDilindungi.contains(_kunciDiff(e) ?? '')
                ? barisLama[_kunciDiff(e)]
                : e,
        ];
        onData(_hasilDaftar(tampil,
            dariServer: true,
            idBaru: idBaru,
            idBerubah: idBerubah,
            jumlahHapus: jumlahHapus,
            fieldData: fieldData,
            total: (hasil['total'] as num?)?.toInt()));
      } else {
        onData({...hasil, 'dariServer': true});
      }
    } on ApiException catch (e) {
      if (!e.offline) rethrow;
      if (lokal == null) rethrow; // belum pernah online -> biarkan layar tahu.
      // Offline dgn cache sudah tampil: cukup diam (indikator offline global
      // sudah menceritakan kondisinya).
    }
  }

  /// Muat daftar master: server dulu (snapshot disimpan ke cache), offline ->
  /// snapshot terakhir + `{offline: true}`. [petaData] mengambil List dari
  /// respons (default field 'data').
  static Future<Map<String, dynamic>> daftarDenganCache(
    String aksi,
    Map<String, dynamic> body,
    String cacheKey, {
    String fieldData = 'data',
  }) async {
    pastikanTimer();
    try {
      final hasil = await ApiClient.instance.aksi(aksi, body);
      final data = hasil[fieldData];
      if (data is List) {
        await CoreDb.instance.simpanCacheReferensi(cacheKey, jsonEncode(data));
      }
      return hasil;
    } on ApiException catch (e) {
      if (!e.offline) rethrow;
      final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
      if (tersimpan == null) rethrow; // belum pernah online -> apa adanya.
      return {
        'status': '00',
        fieldData: jsonDecode(tersimpan),
        'offline': true,
      };
    }
  }

  /// Terapkan satu baris ke snapshot daftar (optimistis, saat offline).
  /// Cocokkan lewat 'id' bila ada; tanpa 'id' (create offline) baris
  /// ditambahkan di depan dengan penanda `_offline: true` utk ditampilkan
  /// berbeda oleh layar bila mau. [kunci] ikut disimpan sebagai `_kunci`
  /// supaya baris (terutama create tanpa id) tetap bisa menampilkan
  /// indikator per-baris (lihat kunciBarisMaster).
  static Future<void> terapkanLokal(String cacheKey, Map<String, dynamic> row,
      {bool hapus = false, String? kunci}) async {
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
    final List daftar = tersimpan == null ? [] : (jsonDecode(tersimpan) as List);
    final id = row['id'];
    final indeks = id == null
        ? -1
        : daftar.indexWhere((e) => e is Map && '${e['id']}' == '$id');
    if (hapus) {
      if (indeks >= 0) daftar.removeAt(indeks);
    } else if (indeks >= 0) {
      daftar[indeks] = {
        ...daftar[indeks] as Map,
        ...row,
        '_offline': true,
        if (kunci != null) '_kunci': kunci,
      };
    } else {
      daftar.insert(0, {
        ...row,
        '_offline': true,
        if (kunci != null) '_kunci': kunci,
      });
    }
    await CoreDb.instance.simpanCacheReferensi(cacheKey, jsonEncode(daftar));
  }

  /// Kirim ulang seluruh antrean PENDING. Aman dipanggil kapan pun; berhenti
  /// pada kegagalan jaringan pertama (masih offline). Return jumlah terkirim.
  static Future<int> flush() async {
    if (_sedangFlush) return 0;
    _sedangFlush = true;
    var terkirim = 0;
    try {
      final pending = await CoreDb.instance.outboxMasterPending();
      if (pending.isEmpty) return 0;
      await _muatUlangHitungan(paksaFase: FaseSinkron.mengirim);
      for (final row in pending) {
        final id = (row['id'] as num).toInt();
        final aksi = '${row['aksi']}';
        final kunci = row['kunci'] == null ? null : '${row['kunci']}';
        Map<String, dynamic> body;
        try {
          body = Map<String, dynamic>.from(
              jsonDecode('${row['payload_json']}') as Map);
        } catch (e) {
          await CoreDb.instance.outboxMasterTandaiGagal(id, 'Payload rusak: $e');
          _tandaiBarisGagal(kunci);
          continue;
        }
        try {
          await ApiClient.instance.aksi(aksi, body);
          await CoreDb.instance.outboxMasterTandaiSukses(id);
          _tandaiBarisSukses(kunci);
          terkirim++;
        } on ApiException catch (e) {
          if (e.offline) {
            await CoreDb.instance.outboxMasterCatatPercobaan(id, e.pesan);
            break; // masih offline -- sisanya pasti gagal juga, coba nanti.
          }
          // Server menolak scr bisnis -> permanen (terlihat, tidak diretry).
          await CoreDb.instance.outboxMasterTandaiGagal(id, e.pesan);
          _tandaiBarisGagal(kunci);
        }
      }
    } finally {
      _sedangFlush = false;
      if (terkirim > 0) {
        // Fase "baru tersinkron" sesaat -> indikator menganimasikan centang,
        // lalu kembali ke fase kalkulasi normal.
        await _muatUlangHitungan(paksaFase: FaseSinkron.baruTersinkron);
        _timerKembaliDiam?.cancel();
        _timerKembaliDiam = Timer(const Duration(seconds: 3), () {
          _muatUlangHitungan();
        });
      } else {
        await _muatUlangHitungan();
      }
    }
    return terkirim;
  }
}
