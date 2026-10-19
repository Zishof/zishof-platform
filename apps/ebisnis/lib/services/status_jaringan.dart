import 'dart:async';

import '../api_client.dart';

enum StatusJaringanPos { memeriksa, online, tidakStabil, offline }

class HasilStatusJaringan {
  final StatusJaringanPos status;
  final DateTime waktu;
  final Duration? durasi;
  final String? pesan;

  const HasilStatusJaringan({
    required this.status,
    required this.waktu,
    this.durasi,
    this.pesan,
  });

  bool get online => status == StatusJaringanPos.online;

  /// True bila koneksi ke server berhasil merespons (baik cepat maupun dengan latensi),
  /// sehingga transaksi yang memerlukan server tetap dapat diproses.
  bool get terhubung =>
      status == StatusJaringanPos.online ||
      status == StatusJaringanPos.tidakStabil;

  /// True bila koneksi tidak terputus total.
  bool get bisaTransaksiOnline => status != StatusJaringanPos.offline;
}

class StatusJaringan {
  StatusJaringan._();

  static final instance = StatusJaringan._();

  HasilStatusJaringan _terakhir = HasilStatusJaringan(
    status: StatusJaringanPos.memeriksa,
    waktu: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Future<HasilStatusJaringan>? _sedangMemeriksa;

  HasilStatusJaringan get terakhir => _terakhir;

  Future<HasilStatusJaringan> periksaSekarang({bool paksa = false}) {
    final berjalan = _sedangMemeriksa;
    if (berjalan != null) return berjalan;
    final now = DateTime.now();
    // Cache ringan 5 detik jika status terakhir sudah online dan tidak dipaksa,
    // mencegah spam panggilan beruntun saat kasir menekan tombol berulang.
    if (!paksa &&
        _terakhir.status == StatusJaringanPos.online &&
        now.difference(_terakhir.waktu) < const Duration(seconds: 5)) {
      return Future.value(_terakhir);
    }
    final future = _periksa();
    _sedangMemeriksa = future;
    return future.whenComplete(() => _sedangMemeriksa = null);
  }

  Future<HasilStatusJaringan> _periksa() async {
    final mulai = DateTime.now();
    try {
      await ApiClient.instance.aksi('error_log_health');
      final durasi = DateTime.now().difference(mulai);
      // Toleransi 12 detik: selama server merespons sukses dalam 12 detik,
      // status dikategorikan Online stabil. Jika lebih dari 12 detik,
      // status tetap terhubung namun dikategorikan tidakStabil untuk indikator visual.
      final status = durasi > const Duration(seconds: 12)
          ? StatusJaringanPos.tidakStabil
          : StatusJaringanPos.online;
      return _terakhir = HasilStatusJaringan(
        status: status,
        waktu: DateTime.now(),
        durasi: durasi,
      );
    } on ApiException catch (error) {
      return _terakhir = HasilStatusJaringan(
        status: error.offline
            ? StatusJaringanPos.offline
            : StatusJaringanPos.tidakStabil,
        waktu: DateTime.now(),
        pesan: error.pesan,
      );
    } catch (error) {
      final teks = '$error'.toLowerCase();
      final terputus = teks.contains('socket') ||
          teks.contains('timeout') ||
          teks.contains('connection refused') ||
          teks.contains('failed host lookup') ||
          teks.contains('network is unreachable');
      return _terakhir = HasilStatusJaringan(
        status: terputus
            ? StatusJaringanPos.offline
            : StatusJaringanPos.tidakStabil,
        waktu: DateTime.now(),
        pesan: '$error',
      );
    }
  }
}
