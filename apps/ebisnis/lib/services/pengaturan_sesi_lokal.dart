import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan sesi lokal per perangkat.
///
/// Server belum memberi kontrak pasti masa berlaku token, jadi aplikasi
/// menerapkan batas lokal: token dilupakan bila app dibuka lagi setelah
/// terlalu lama ditutup/background.
class PengaturanSesiLokal {
  PengaturanSesiLokal._();
  static final PengaturanSesiLokal instance = PengaturanSesiLokal._();

  static const defaultTimeoutMenit = 60;
  static const minTimeoutMenit = 1;
  static const maxTimeoutMenit = 10080; // 7 hari

  static const _kTimeoutMenit = 'session_timeout_minutes';
  static const _kTerakhirAktif = 'session_last_active_at';

  int timeoutMenit = defaultTimeoutMenit;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    timeoutMenit = _normalisasi(sp.getInt(_kTimeoutMenit));
  }

  Future<void> simpanTimeoutMenit(int menit) async {
    timeoutMenit = _normalisasi(menit);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kTimeoutMenit, timeoutMenit);
  }

  Future<void> catatAktifSekarang() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kTerakhirAktif, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> hapusCatatanAktif() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kTerakhirAktif);
  }

  Future<bool> sudahKedaluwarsa() async {
    await muat();
    final sp = await SharedPreferences.getInstance();
    final terakhirAktifMs = sp.getInt(_kTerakhirAktif);
    if (terakhirAktifMs == null) return false;

    final terakhirAktif = DateTime.fromMillisecondsSinceEpoch(terakhirAktifMs);
    final batas = Duration(minutes: timeoutMenit);
    return DateTime.now().difference(terakhirAktif) > batas;
  }

  int _normalisasi(int? menit) {
    final nilai = menit ?? defaultTimeoutMenit;
    return nilai.clamp(minTimeoutMenit, maxTimeoutMenit).toInt();
  }
}
