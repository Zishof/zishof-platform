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
    int? idLokal,
    String entitas = 'master',
  }) async {
    pastikanTimer();
    final antreBody = <String, dynamic>{
      ...body,
      'client_mutation_id':
          '${kunci ?? aksi}:${DateTime.now().microsecondsSinceEpoch}',
      // Baris BARU yang dibuat offline membawa id sementaranya sendiri supaya
      // pasangannya bisa dicatat begitu server memberi id sungguhan.
      if (idLokal != null) 'id_lokal': idLokal,
    };
    if (idLokal != null) {
      await CoreDb.instance.idSementaraCatat(idLokal, entitas);
    }
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
      // Rujukan ke baris yang dibuat offline ditukar dgn id server yang sudah ada;
      // bila pembuatnya belum terkirim, kiriman ini ditahan (tetap antre).
      final peta = await CoreDb.instance.idSementaraTerpetakan();
      final siap = await tukarIdSementara(body, peta);
      if (siap == null) {
        throw ApiException(
            'Menunggu data induk yang dibuat offline selesai terkirim.',
            offline: true,
            aktivitas: aksi);
      }
      final hasil = await ApiClient.instance.aksi(aksi, siap);
      await _catatPemetaan(siap, hasil);
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

  // ==================== ID SEMENTARA UNTUK BARIS OFFLINE ====================
  //
  // Baris master yang dibuat saat offline belum punya id server, padahal baris lain
  // bisa langsung menunjuknya (Penggunaan Anggaran -> item anggaran, Bank -> akun).
  // Klien memberi id SEMENTARA bernilai negatif; saat antrean dikirim, setiap rujukan
  // ke id itu ditukar dengan id sungguhan yang sudah diketahui. Rujukan yang belum
  // punya pasangan DITAHAN (bukan dikirim apa adanya) supaya tidak pernah ada baris
  // yang menunjuk data yang belum ada di server.

  static int _urutIdSementara = 0;

  /// Id sementara baru: NEGATIF (id server selalu positif, jadi mustahil bentrok)
  /// dan menaik sehingga unik lintas entitas pada satu perangkat.
  static int idSementaraBaru() {
    _urutIdSementara = (_urutIdSementara + 1) % 1000;
    return -(DateTime.now().millisecondsSinceEpoch * 1000 + _urutIdSementara);
  }

  static bool _idSementara(Object? v) => v is int && v < 0;

  /// Kolom yang isinya RUJUKAN id -- hanya kolom inilah yang boleh ditukar. Menukar
  /// semua bilangan negatif berbahaya: nominal debet/kredit pun bisa negatif.
  static bool _kolomId(String kunci) {
    final k = kunci.toLowerCase();
    return k == 'id' ||
        k.endsWith('id') && !k.endsWith('void') ||
        k.endsWith('_id');
  }

  /// Tukar seluruh rujukan id sementara di [body] dengan id server yang sudah
  /// diketahui. Mengembalikan null bila masih ada rujukan yang BELUM punya
  /// pasangan -- pemanggil wajib menahan pengiriman baris itu.
  static Future<Map<String, dynamic>?> tukarIdSementara(
      Map<String, dynamic> body, Map<int, int> peta) async {
    var tertunda = false;

    Object? telusuri(String kunci, Object? nilai) {
      if (nilai is Map) {
        return {
          for (final e in nilai.entries)
            '${e.key}': telusuri('${e.key}', e.value)
        };
      }
      if (nilai is List) {
        return [for (final e in nilai) telusuri(kunci, e)];
      }
      if (_kolomId(kunci) && _idSementara(nilai)) {
        final server = peta[nilai as int];
        if (server == null) {
          // Kekecualian: 'id_lokal' memang MENYIMPAN id sementaranya sendiri.
          if (kunci.toLowerCase() != 'id_lokal') tertunda = true;
          return nilai;
        }
        return server;
      }
      return nilai;
    }

    final hasil = <String, dynamic>{
      for (final e in body.entries) e.key: telusuri(e.key, e.value)
    };
    return tertunda ? null : hasil;
  }

  /// Catat pasangan id sementara -> id server setelah baris pembuatnya terkirim.
  static Future<void> _catatPemetaan(
      Map<String, dynamic> body, Map<String, dynamic> hasil) async {
    final lokal = body['id_lokal'];
    final server = hasil['id'];
    if (lokal is int && lokal < 0 && server is num) {
      await CoreDb.instance.idSementaraPetakan(lokal, server.toInt());
      // Sekali terpetakan, baris antrean lain yang menunggunya bisa ikut jalan.
      revisiBaris.value++;
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
        // 'total' bisa berupa objek agregat pd sebagian aksi -- jangan
        // di-cast paksa (lihat catatan di daftarCacheDulu).
        final totalMentah = hasil['total'];
        total = total ?? (totalMentah is num ? totalMentah.toInt() : null);
        if (lapor != null) lapor(semua.length, total);
        final habis =
            data.length < pageSize || (total != null && semua.length >= total);
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
      int? total,
      Map<String, dynamic>? responsAsli}) {
    return {
      // Field top-level LAIN dari respons server diteruskan apa adanya --
      // banyak layar membaca ringkasan/summary/totalOutstanding/daftarKasir
      // di samping barisnya. Membuangnya membuat KPI layar diam-diam nol
      // (ditemukan saat konversi hutang/piutang 2026-08-19).
      ...?responsAsli,
      'status': '00',
      /* Baris yang dihapus secara lokal disaring DI SINI, satu tempat untuk
       * seluruh layar. Menyaringnya di tiap layar berarti setiap layar baru
       * harus ingat melakukannya, dan yang lupa akan menampilkan baris yang
       * menurut penggunanya sudah dihapus. Barisnya sendiri tetap tersimpan
       * di snapshot supaya penghapusannya masih dapat dibatalkan. */
      fieldData:
          data.where((e) => !(e is Map && e['_dihapus'] == true)).toList(),
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

  /// Kunci baris versi PUBLIK -- dipakai layar utk `KilauBaris(kunci: ...)`
  /// supaya persis sama dengan kunci diff internal. WAJIB dipakai bila layar
  /// menyetel [kolomKunci] pada [daftarCacheDulu]; memakai nilai kolom
  /// telanjang membuat kilau tidak pernah menyala.
  static String kunciBaris(dynamic row, [String? kolomKunci]) =>
      _kunciDiff(row, kolomKunci) ?? '';

  /// Kunci identitas satu baris daftar. Urutan: [kolomKunci] bila diberikan
  /// layar (mis. 'produkId'/'fakturId' utk daftar yang server-nya tidak
  /// mengirim kolom 'id'), lalu 'id', lalu '_kunci' (draf create offline).
  /// Baris tanpa ketiganya TIDAK bisa di-diff maupun di-merge dengan aman.
  static String? _kunciDiff(dynamic e, [String? kolomKunci]) {
    if (e is! Map) return null;
    if (kolomKunci != null) {
      final alt = e[kolomKunci];
      if (alt != null) return '$kolomKunci=$alt';
    }
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
    String? kolomKunci,
  }) async {
    pastikanTimer();
    List? lokal;
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
    if (tersimpan != null) {
      try {
        lokal = jsonDecode(tersimpan) as List;
        onData(_hasilDaftar(lokal, dariServer: false, fieldData: fieldData));
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
          final k = _kunciDiff(e, kolomKunci);
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
          final k = _kunciDiff(e, kolomKunci);
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
        // Sebagian aksi memakai 'total' utk OBJEK agregat (mis.
        // pembantu_piutang_list), bukan cacah baris -- jangan di-cast paksa.
        final totalMentah = hasil['total'];
        final totalServer = totalMentah is num ? totalMentah.toInt() : null;
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
              kunciDilindungi.contains(_kunciDiff(e, kolomKunci) ?? '')
                  ? barisLama[_kunciDiff(e, kolomKunci)]
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
          // Baris TANPA kunci tidak bisa dicocokkan antar-muat. Menyimpannya
          // dgn nomor urut membuat cache menggandakan diri tiap refresh
          // (ditemukan saat konversi daftar Inventory & Sales yang server-nya
          // tidak mengirim kolom 'id'). Aturan: bila respons server memuat
          // baris tanpa kunci, baris tanpa kunci versi LOKAL dibuang dan
          // digantikan versi server; layar yang barisnya memang tak ber-id
          // sebaiknya menyetel [kolomKunci].
          final adaServerTanpaKunci =
              data.any((e) => _kunciDiff(e, kolomKunci) == null);
          final tanpaKunciServer = <dynamic>[];
          final tanpaKunciLokal = <dynamic>[];
          for (final e in (lokal ?? const [])) {
            final k = _kunciDiff(e, kolomKunci);
            if (k != null) {
              petaGabung[k] = e;
            } else if (!adaServerTanpaKunci) {
              tanpaKunciLokal.add(e);
            }
          }
          for (final e in data) {
            final k = _kunciDiff(e, kolomKunci);
            if (k != null) {
              if (!kunciDilindungi.contains(k)) petaGabung[k] = e;
            } else {
              tanpaKunciServer.add(e);
            }
          }
          gabungan = [
            ...tanpaKunciLokal,
            ...petaGabung.values,
            ...tanpaKunciServer,
          ];
        }
        await CoreDb.instance
            .simpanCacheReferensi(cacheKey, jsonEncode(gabungan));
        // Yang ditampilkan pun memakai versi lokal utk baris terlindungi.
        final tampil = [
          for (final e in data)
            kunciDilindungi.contains(_kunciDiff(e, kolomKunci) ?? '')
                ? barisLama[_kunciDiff(e, kolomKunci)]
                : e,
        ];
        onData(_hasilDaftar(tampil,
            dariServer: true,
            idBaru: idBaru,
            idBerubah: idBerubah,
            jumlahHapus: jumlahHapus,
            fieldData: fieldData,
            total: totalServer,
            responsAsli: hasil));
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
    final List daftar =
        tersimpan == null ? [] : (jsonDecode(tersimpan) as List);
    final id = row['id'];
    final indeks = id == null
        ? -1
        : daftar.indexWhere((e) => e is Map && '${e['id']}' == '$id');
    if (hapus) {
      /* HAPUS LOKAL BERSIFAT LUNAK. Barisnya TIDAK dibuang dari snapshot,
       * melainkan ditandai. Alasannya: penghapusan yang dikerjakan saat offline
       * baru sampai ke server belakangan, dan sampai saat itu satu-satunya
       * salinan datanya ada di perangkat ini. Membuangnya seketika berarti
       * salah tekan tidak dapat dipulihkan sama sekali.
       *
       * Baris bertanda ini disaring di [daftarCacheDulu] sehingga tidak tampil
       * di layar mana pun -- pengguna melihatnya seolah benar-benar terhapus --
       * dan dibersihkan sendiri ketika daftarnya dimuat ulang dari server, yang
       * memang tidak lagi mengirimkannya. Pemulihannya lewat [pulihkanLokal].
       *
       * Sisi server tidak memerlukan ini: di sana sudah ada AuditTrails. */
      if (indeks >= 0) {
        daftar[indeks] = {
          ...daftar[indeks] as Map,
          '_dihapus': true,
          '_dihapusPada': DateTime.now().toIso8601String(),
          if (kunci != null) '_kunci': kunci,
        };
      }
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

  /// Batalkan penghapusan lokal sebuah baris.
  ///
  /// Dua hal dikerjakan sekaligus, dan keduanya wajib: tanda hapus pada snapshot
  /// dilepas, DAN perintah hapus yang masih mengantre dibuang. Melewatkan yang
  /// kedua berarti barisnya kembali tampil di layar tetapi tetap terhapus di
  /// server begitu jaringan tersambung -- kegagalan yang paling membingungkan
  /// karena tampak berhasil lebih dulu.
  ///
  /// Mengembalikan true bila memang ada baris yang dipulihkan.
  static Future<bool> pulihkanLokal(String cacheKey, Object id,
      {String? kunci}) async {
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
    if (tersimpan == null) return false;
    final List daftar = jsonDecode(tersimpan) as List;
    final indeks = daftar.indexWhere((e) => e is Map && '${e['id']}' == '$id');
    if (indeks < 0) return false;
    final baris = Map<String, dynamic>.from(daftar[indeks] as Map);
    if (baris['_dihapus'] != true) return false;
    baris.remove('_dihapus');
    baris.remove('_dihapusPada');
    daftar[indeks] = baris;
    await CoreDb.instance.simpanCacheReferensi(cacheKey, jsonEncode(daftar));
    final kunciAntrean = kunci ?? '${baris['_kunci'] ?? ''}';
    if (kunciAntrean.isNotEmpty) {
      await CoreDb.instance.outboxMasterHapusKunci(kunciAntrean);
    }
    await _muatUlangHitungan();
    return true;
  }

  /// Baris yang sedang bertanda terhapus pada satu cache, terbaru lebih dahulu.
  /// Dipakai layar pemulihan untuk menawarkan pengembalian.
  static Future<List<Map<String, dynamic>>> daftarTerhapusLokal(
      String cacheKey) async {
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
    if (tersimpan == null) return const [];
    final List daftar = jsonDecode(tersimpan) as List;
    final hasil = daftar
        .whereType<Map>()
        .where((e) => e['_dihapus'] == true)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    hasil.sort((a, b) =>
        '${b['_dihapusPada'] ?? ''}'.compareTo('${a['_dihapusPada'] ?? ''}'));
    return hasil;
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
          await CoreDb.instance
              .outboxMasterTandaiGagal(id, 'Payload rusak: $e');
          _tandaiBarisGagal(kunci);
          continue;
        }
        // Tukar rujukan id sementara -> id server. Peta dibaca ULANG tiap baris
        // karena baris sebelumnya dalam putaran ini mungkin baru saja mengisinya.
        final peta = await CoreDb.instance.idSementaraTerpetakan();
        final siap = await tukarIdSementara(body, peta);
        if (siap == null) {
          // Induknya belum terkirim -- lewati dulu, jangan ditandai gagal.
          continue;
        }
        try {
          final hasil = await ApiClient.instance.aksi(aksi, siap);
          await _catatPemetaan(siap, hasil);
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
        // Pemetaan id sementara yang sudah lama selesai tidak dirujuk siapa pun lagi;
        // dibersihkan berkala supaya tabelnya tidak tumbuh tanpa batas.
        unawaited(CoreDb.instance.idSementaraBersihkan());
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
