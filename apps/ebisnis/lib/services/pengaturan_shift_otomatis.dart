import 'package:shared_preferences/shared_preferences.dart';

class PengaturanShiftOtomatis {
  PengaturanShiftOtomatis._();
  static final instance = PengaturanShiftOtomatis._();

  static const _buka = 'shift_otomatis_buka';
  static const _modal = 'shift_otomatis_modal_awal';
  static const _tutup = 'shift_otomatis_tutup';
  static const _jam = 'shift_otomatis_jam_tutup';

  bool bukaOtomatis = false;
  double modalAwal = 0;
  bool ingatkanTutupOtomatis = false;
  String jamTutup = '22:00';

  Future<void> muat() async {
    final p = await SharedPreferences.getInstance();
    bukaOtomatis = p.getBool(_buka) ?? false;
    modalAwal = p.getDouble(_modal) ?? 0;
    ingatkanTutupOtomatis = p.getBool(_tutup) ?? false;
    jamTutup = p.getString(_jam) ?? '22:00';
  }

  Future<void> simpan({
    required bool bukaOtomatis,
    required double modalAwal,
    required bool ingatkanTutupOtomatis,
    required String jamTutup,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_buka, bukaOtomatis);
    await p.setDouble(_modal, modalAwal);
    await p.setBool(_tutup, ingatkanTutupOtomatis);
    await p.setString(_jam, jamTutup);
    await muat();
  }
}
