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

  Future<HasilStatusJaringan> periksaSekarang() {
    final berjalan = _sedangMemeriksa;
    if (berjalan != null) return berjalan;
    final future = _periksa();
    _sedangMemeriksa = future;
    return future.whenComplete(() => _sedangMemeriksa = null);
  }

  Future<HasilStatusJaringan> _periksa() async {
    final mulai = DateTime.now();
    try {
      await ApiClient.instance.aksi('error_log_health');
      final durasi = DateTime.now().difference(mulai);
      final status = durasi > const Duration(seconds: 8)
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
      return _terakhir = HasilStatusJaringan(
        status: StatusJaringanPos.tidakStabil,
        waktu: DateTime.now(),
        pesan: '$error',
      );
    }
  }
}
