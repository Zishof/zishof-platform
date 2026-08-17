import 'package:shared_preferences/shared_preferences.dart';

import '../app_variant.dart';

/// Preferensi koreksi transaksi lunas pada perangkat ini.
///
/// Ini adalah lapisan UX tambahan di atas otorisasi admin/supervisor dari
/// server. Menyalakan sakelar tidak pernah memberi hak kepada kasir biasa;
/// server tetap memeriksa kewenangan pada setiap permintaan koreksi.
class PengaturanKoreksiTransaksi {
  PengaturanKoreksiTransaksi._();

  static final PengaturanKoreksiTransaksi instance =
      PengaturanKoreksiTransaksi._();

  static String get _kunci =>
      '${AppVariant.storageNamespace}_izinkan_edit_transaksi_lunas';

  bool izinkanEdit = true;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    // Default aktif mempertahankan perilaku versi lama. Supervisor dapat
    // menonaktifkannya eksplisit dari Konfigurasi pada perangkat ini.
    izinkanEdit = sp.getBool(_kunci) ?? true;
  }

  Future<void> simpan(bool nilai) async {
    izinkanEdit = nilai;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kunci, nilai);
  }
}
