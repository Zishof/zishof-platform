import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../sesi.dart';
import 'pelayanan_transaksi.dart';

/// Pengirim ulang transaksi POS yang sudah ditulis ke SQLite sebelum request
/// pertama dilakukan. Satu instance hidup selama aplikasi berjalan sehingga
/// retry tidak bergantung pada layar Kasir sedang terbuka atau tombol Sinkron
/// ditekan pengguna.
///
/// Kegagalan jaringan/timeout dan gangguan teknis server terus dicoba sesuai
/// interval yang dapat dikonfigurasi. Penolakan bisnis yang pasti
/// (stok/saldo/hak akses/payload tidak valid) ditandai GAGAL agar tidak
/// membanjiri server. Semua retry memakai `kode_unik` asli, sehingga aman
/// terhadap respons yang hilang setelah server sempat menyimpan transaksi.
class TransaksiOutboxService {
  TransaksiOutboxService._();

  static final TransaksiOutboxService instance = TransaksiOutboxService._();
  static const int intervalRetryMenitDefault = 10;
  static const String _kunciIntervalRetry =
      'transaksi_pending_interval_retry_menit';

  Timer? _timer;
  Timer? _retryTertunda;
  Future<HasilSinkronisasiTransaksi>? _prosesAktif;
  bool _sedangMemulai = false;
  int _intervalRetryMenit = intervalRetryMenitDefault;

  int get intervalRetryMenit => _intervalRetryMenit;

  void mulai() {
    if (_timer != null || _sedangMemulai) return;
    _sedangMemulai = true;
    unawaited(_mulaiInternal());
  }

  Future<void> _mulaiInternal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _intervalRetryMenit = _normalisasiInterval(
          sp.getInt(_kunciIntervalRetry) ?? intervalRetryMenitDefault);
      _pasangTimer();
    } finally {
      _sedangMemulai = false;
    }
    unawaited(sinkronkan());
  }

  int _normalisasiInterval(int menit) => menit.clamp(1, 1440).toInt();

  void _pasangTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
        Duration(minutes: _intervalRetryMenit), (_) => unawaited(sinkronkan()));
  }

  void _jadwalkanRetrySetelahJeda() {
    if (_retryTertunda?.isActive ?? false) return;
    _retryTertunda = Timer(Duration(minutes: _intervalRetryMenit), () {
      _retryTertunda = null;
      unawaited(sinkronkan());
    });
  }

  Future<void> aturIntervalRetryMenit(int menit) async {
    _intervalRetryMenit = _normalisasiInterval(menit);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kunciIntervalRetry, _intervalRetryMenit);
    _pasangTimer();
  }

  Future<int> muatIntervalRetryMenit() async {
    final sp = await SharedPreferences.getInstance();
    _intervalRetryMenit = _normalisasiInterval(
        sp.getInt(_kunciIntervalRetry) ?? intervalRetryMenitDefault);
    return _intervalRetryMenit;
  }

  Future<HasilSinkronisasiTransaksi> sinkronkan() {
    final aktif = _prosesAktif;
    if (aktif != null) return aktif;
    final proses = _sinkronkanInternal();
    _prosesAktif = proses;
    return proses.whenComplete(() => _prosesAktif = null);
  }

  /// Dipanggil tepat setelah transaksi committed ke SQLite. Jika proses lama
  /// sedang berjalan, tunggu proses itu berakhir lalu lakukan satu sapuan baru
  /// supaya baris yang baru masuk tidak harus menunggu timer periodik.
  void kirimDiBackground() {
    unawaited(_kirimSaatSiap());
  }

  Future<void> _kirimSaatSiap() async {
    final aktif = _prosesAktif;
    if (aktif != null) await aktif;
    await sinkronkan();
  }

  Future<HasilSinkronisasiTransaksi> _sinkronkanInternal() async {
    if (!ApiClient.instance.sudahLogin) {
      return const HasilSinkronisasiTransaksi(total: 0, berhasil: 0);
    }

    final pending = await CoreDb.instance.transaksiPendingBelumSinkron(
      akunKunci: Sesi.instance.userId,
      tokoId: Sesi.instance.tokoId,
      idPerangkat: IdentitasMesin.instance.idMesin,
    );
    var berhasil = 0;
    for (final row in pending) {
      final kodeUnik = '${row['kode_unik'] ?? ''}';
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
            jsonDecode('${row['payload_json']}') as Map);
      } catch (e) {
        await CoreDb.instance.tandaiTransaksiDitolak(
            kodeUnik, 'Payload lokal rusak dan tidak dapat dikirim: $e');
        continue;
      }

      // Proteksi migrasi utk baris lama yang belum memiliki akun_kunci.
      // Jangan pernah kirim transaksi milik akun/toko lain memakai token
      // pengguna yang sedang login sekarang.
      final kasirPayload = '${payload['kasir'] ?? ''}'.trim();
      final tokoPayload = (payload['tokoId'] ?? payload['idToko']) as Object?;
      final tokoPayloadInt = tokoPayload is num
          ? tokoPayload.toInt()
          : int.tryParse('$tokoPayload');
      final pemulihanSupervisor =
          payload['input_supervisor'] == true && Sesi.instance.bolehKelola;
      if ((!pemulihanSupervisor &&
              kasirPayload.isNotEmpty &&
              kasirPayload != Sesi.instance.userId) ||
          (tokoPayloadInt != null && tokoPayloadInt != Sesi.instance.tokoId) ||
          ('${payload['id_perangkat'] ?? ''}'.trim().isNotEmpty &&
              '${payload['id_perangkat']}'.trim() !=
                  IdentitasMesin.instance.idMesin)) {
        continue;
      }

      try {
        payload['pengiriman_pending'] = true;
        final hasilBayar = await ApiClient.instance.aksi('bayar', payload);
        await PelayananTransaksi.tandaiJikaPerlu(
          payload: payload,
          hasilBayar: hasilBayar,
          percobaanCari: 1,
        );
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
        berhasil++;
      } catch (e) {
        final pesan = e.toString();
        if (_transaksiSudahAdaDiServer(e)) {
          await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
          berhasil++;
          continue;
        }
        await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
        if (dapatDicobaUlang(e)) {
          _jadwalkanRetrySetelahJeda();
          if (e is ApiException && e.offline) {
            // Koneksi masih putus. Berhenti agar baris berikutnya tidak ikut
            // menghasilkan error yang sama; timer akan mencoba lagi sesuai
            // interval yang dikonfigurasi.
            break;
          }
          // Error teknis server dapat bersifat khusus pada satu payload.
          // Biarkan tetap PENDING, lalu lanjutkan transaksi berikutnya.
          continue;
        }
        // Penolakan bisnis yang pasti tidak akan membaik hanya dengan retry
        // (mis. stok/saldo/hak akses). Simpan sebagai GAGAL untuk audit, jangan
        // hapus, dan jangan membanjiri server setiap interval.
        await CoreDb.instance.tandaiTransaksiDitolak(kodeUnik, pesan);
      }
    }
    // Setiap POS menyimpan pula transaksi kasir lain pada toko yang sama.
    // Endpoint server mengunci toko dari sesi login, sehingga payload toko
    // palsu tidak dapat mengambil data outlet lain. Rentang tiga hari cukup
    // untuk menutup pergantian hari/koneksi putus tanpa mengunduh seluruh
    // histori besar pada setiap siklus 10 menit.
    try {
      await _cadangkanTransaksiTokoTerbaru();
    } catch (_) {
      // Replikasi cadangan bersifat best-effort dan tidak boleh mengubah hasil
      // pengiriman transaksi utama. Timer periodik akan mencoba kembali.
      _jadwalkanRetrySetelahJeda();
    }
    return HasilSinkronisasiTransaksi(
        total: pending.length, berhasil: berhasil);
  }

  Future<void> _cadangkanTransaksiTokoTerbaru() async {
    final tokoId = Sesi.instance.tokoId;
    if (tokoId == null) return;
    final lokal = await CoreDb.instance
        .transaksiArsipLokal(tokoId: tokoId, limit: 1000000);
    final kodeLokal = lokal
        .map((row) => '${row['kode_unik'] ?? ''}'.trim().toLowerCase())
        .where((kode) => kode.isNotEmpty)
        .toSet();
    final sekarang = DateTime.now();
    final mulai = sekarang.subtract(const Duration(days: 2));
    var page = 1;
    while (page <= 20) {
      final hasil =
          await ApiClient.instance.aksi('transaksi_backup_toko_list', {
        'toko_id': tokoId,
        'tglMulai': _tanggal(mulai),
        'tglSampai': _tanggal(sekarang),
        'page': page,
        'pageSize': 100,
      });
      final daftar = ((hasil['data'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      for (final row in daftar) {
        final kode = _kodeServer(row);
        if (kode.isEmpty || kodeLokal.contains(kode.toLowerCase())) continue;
        final id = row['idTransaksi'];
        if (id == null) continue;
        final detail = await ApiClient.instance.aksi('detail_transaksi', {
          'id': id,
          'toko_id': tokoId,
        });
        final items = ((detail['item'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => <String, dynamic>{
                  'id': item['produkId'] ?? item['id'],
                  'kode': item['kode'],
                  'nama': item['nama'],
                  'harga': item['harga'] ?? 0,
                  'jumlah': item['qty'] ?? item['jumlah'] ?? 0,
                  'diskon': item['diskon'] ?? 0,
                  'cashback': item['cashback'] ?? 0,
                })
            .toList();
        final username =
            '${detail['kasirUserId'] ?? row['kasirUserId'] ?? row['kasir'] ?? ''}'
                .trim();
        final idPerangkat =
            '${detail['idPerangkat'] ?? row['idPerangkat'] ?? ''}'.trim();
        final namaMesin = '${row['namaMesin'] ?? ''}'.trim();
        final payload = <String, dynamic>{
          'kodeUnik': kode,
          'clientTrxId': kode,
          'idToko': tokoId,
          'tokoId': tokoId,
          'kasir': username,
          'kasir_user_id': username,
          'waktu': '${detail['waktu'] ?? row['waktu'] ?? ''}',
          'caraBayarNama': '${row['metode'] ?? ''}',
          'total': detail['totalBiaya'] ?? row['totalBiaya'] ?? 0,
          'pajak': row['pajak'] ?? 0,
          'nama_member': detail['pembeli'] ?? row['pembeli'],
          'nama_mesin': namaMesin,
          'id_perangkat': idPerangkat,
          'sumber_username': username,
          'sumber_mesin': namaMesin.isNotEmpty ? namaMesin : idPerangkat,
          'asal_backup': 'REPLIKASI_OTOMATIS_TOKO_SAMA',
          'transaksi': items,
        };
        final tersimpan = await CoreDb.instance.simpanTransaksiDariServer(
            kode, jsonEncode(payload),
            akunKunci: username,
            tokoId: tokoId,
            idPerangkat: idPerangkat.isNotEmpty ? idPerangkat : namaMesin);
        if (tersimpan) kodeLokal.add(kode.toLowerCase());
      }
      final total = (hasil['total'] as num?)?.toInt() ?? daftar.length;
      if (daftar.isEmpty || page * 100 >= total || daftar.length < 100) break;
      page++;
    }
  }

  String _tanggal(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _kodeServer(Map<String, dynamic> row) {
    for (final key in const <String>[
      'kodeUnik',
      'clientTrxId',
      'kodeTransaksi',
      'nomorTransaksi',
      'nomorNota',
      'kode'
    ]) {
      final nilai = '${row[key] ?? ''}'.trim();
      if (nilai.isEmpty || nilai == '-') continue;
      if (key == 'nomorNota') {
        final cocok = RegExp(r'\(([^()]+)\)\s*$').firstMatch(nilai);
        final kodeLama = cocok?.group(1)?.trim() ?? '';
        if (kodeLama.isNotEmpty) return kodeLama;
      }
      return nilai;
    }
    return '';
  }

  /// Network, HTTP 5xx, respons server yang tidak valid, dan error internal
  /// tanpa kode bisnis adalah kegagalan teknis yang aman dicoba ulang dengan
  /// idempotency key yang sama.
  bool dapatDicobaUlang(Object error) {
    if (error is! ApiException) return true;
    if (error.offline || (error.statusHttp ?? 0) >= 500) return true;
    return (error.kode ?? '').trim().isEmpty;
  }

  bool _transaksiSudahAdaDiServer(Object error) {
    if (error is ApiException &&
        (error.kode ?? '').trim() == 'DUPLIKAT_KODE_TRANSAKSI') {
      return true;
    }
    final pesan = error.toString().toLowerCase();
    return pesan.contains('sudah tercatat') ||
        pesan.contains('kode transaksi yang sama sudah ada') ||
        pesan.contains('duplicate key');
  }
}

class HasilSinkronisasiTransaksi {
  final int total;
  final int berhasil;

  const HasilSinkronisasiTransaksi(
      {required this.total, required this.berhasil});
}
