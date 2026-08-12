import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan cetak Price Tag (ukuran, kertas, salinan, toggle tampilan,
/// kustom warna/teks) disimpan lokal PER MODEL ('rak'/'produk'/'promo')
/// supaya saat halaman Cetak Price Tag dibuka lagi -- atau user pindah tab
/// model -- pengaturan terakhir langsung terpakai tanpa diatur ulang dari
/// awal. Bentuk isi tiap model sengaja bebas (`Map<String, dynamic>`) supaya
/// layar pemanggil (`PriceTagScreen`) yang menentukan field apa saja yang
/// relevan per model, service ini cuma nyimpan & baliknya apa adanya.
class PengaturanPriceTag {
  PengaturanPriceTag._();
  static final PengaturanPriceTag instance = PengaturanPriceTag._();

  static const _kunci = 'price_tag_pengaturan_v1';

  String? _modelTerakhir;
  Map<String, Map<String, dynamic>> _perModel = {};

  String? get modelTerakhir => _modelTerakhir;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kunci);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _modelTerakhir = decoded['modelTerakhir'] as String?;
      final perModel = decoded['perModel'];
      if (perModel is Map) {
        _perModel = perModel.map((k, v) => MapEntry(
              '$k',
              v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
            ));
      }
    } catch (_) {
      // Data lama/korup -- abaikan, layar pemanggil jatuh ke default bawaan.
    }
  }

  Map<String, dynamic>? untukModel(String model) => _perModel[model];

  Future<void> simpan(String modelAktif, Map<String, dynamic> pengaturan) async {
    _modelTerakhir = modelAktif;
    _perModel = {..._perModel, modelAktif: pengaturan};
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kunci,
      jsonEncode({'modelTerakhir': _modelTerakhir, 'perModel': _perModel}),
    );
  }
}
