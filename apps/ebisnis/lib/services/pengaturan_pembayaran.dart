import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Preferensi pembayaran lokal per perangkat/mesin kasir.
///
/// Default operasional tetap Tunai jika tersedia, tetapi supervisor/admin dapat
/// menggantinya dari Konfigurasi tanpa perlu perubahan server.
class PengaturanPembayaran {
  PengaturanPembayaran._();
  static final PengaturanPembayaran instance = PengaturanPembayaran._();

  static const _kunciCaraBayarDefaultId = 'pembayaran_default_cara_bayar_id';

  int? _caraBayarDefaultId;

  int? get caraBayarDefaultId => _caraBayarDefaultId;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    _caraBayarDefaultId = sp.getInt(_kunciCaraBayarDefaultId);
  }

  Future<void> simpan({required int? caraBayarDefaultId}) async {
    _caraBayarDefaultId = caraBayarDefaultId;
    final sp = await SharedPreferences.getInstance();
    if (caraBayarDefaultId == null) {
      await sp.remove(_kunciCaraBayarDefaultId);
    } else {
      await sp.setInt(_kunciCaraBayarDefaultId, caraBayarDefaultId);
    }
  }

  CaraBayar? pilihDefault(List<CaraBayar> daftar) {
    if (daftar.isEmpty) return null;
    final tersimpan = _caraBayarDefaultId;
    if (tersimpan != null) {
      for (final cara in daftar) {
        if (cara.id == tersimpan) return cara;
      }
    }
    for (final cara in daftar) {
      final nama = cara.nama.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (nama == 'tunai' || nama.contains('tunai')) return cara;
    }
    return daftar.first;
  }
}
