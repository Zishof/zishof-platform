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

  /// Interval retry latar. Publik agar test bisa memeriksa kontraknya.
  static const Duration intervalFlush = Duration(seconds: 20);

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
