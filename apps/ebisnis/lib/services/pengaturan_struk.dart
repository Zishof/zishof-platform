import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan struk lokal per perangkat.
///
/// Logo disalin ke folder data aplikasi supaya tetap tersedia walau file asli
/// dari flashdisk/folder unduhan dipindahkan. Jika kosong, struk memakai logo
/// default aplikasi sesuai build variant.
class PengaturanStruk {
  PengaturanStruk._();
  static final PengaturanStruk instance = PengaturanStruk._();

  static const _kunciLogoPath = 'struk_logo_path';
  static const _kunciLogoMode = 'struk_logo_mode';
  static const _kunciLogoSkala = 'struk_logo_skala';
  static const _kunciLebarKertasMm = 'struk_lebar_kertas_mm';
  static const _kunciPriceTagLogoPath = 'price_tag_logo_path';
  static const _kunciPriceTagMarginKotakMm = 'price_tag_margin_kotak_mm';
  static const List<double> opsiLebarKertasMm = [58, 72, 76, 80];

  String? _logoPath;
  String? _priceTagLogoPath;
  String _logoMode = 'persegi';
  double _logoSkala = 1;
  double _lebarKertasMm = 80;
  double _priceTagMarginKotakMm = 2;

  String? get logoPath {
    final path = _logoPath?.trim();
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  String? get priceTagLogoPath {
    final path = _priceTagLogoPath?.trim();
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  String get logoMode => _logoMode;
  bool get logoLandscape => _logoMode == 'landscape';
  double get logoSkala => _logoSkala;
  double get lebarKertasMm => _lebarKertasMm;
  double get priceTagMarginKotakMm => _priceTagMarginKotakMm;
  double get lebarKontenMm => (_lebarKertasMm - 6).clamp(46, 90).toDouble();
  double get lebarPreviewPx =>
      (_lebarKertasMm * 5.2).clamp(300, 460).toDouble();

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    _logoPath = sp.getString(_kunciLogoPath);
    _priceTagLogoPath = sp.getString(_kunciPriceTagLogoPath);
    _logoMode =
        sp.getString(_kunciLogoMode) == 'landscape' ? 'landscape' : 'persegi';
    _logoSkala = (sp.getDouble(_kunciLogoSkala) ?? 1).clamp(0.8, 1.8);
    _lebarKertasMm = _normalisasiLebarKertas(
      sp.getDouble(_kunciLebarKertasMm) ?? 80,
    );
    _priceTagMarginKotakMm = _normalisasiMarginPriceTag(
      sp.getDouble(_kunciPriceTagMarginKotakMm) ?? 2,
    );
  }

  Future<String?> pilihDanSimpanLogo() async {
    final path = await _pilihDanSimpanLogoLokal(
      subfolder: 'struk',
      namaFile: 'logo_struk',
    );
    if (path == null) return null;
    _logoPath = path;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciLogoPath, path);
    return path;
  }

  Future<void> hapusLogo() async {
    final path = _logoPath;
    _logoPath = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kunciLogoPath);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<String?> pilihDanSimpanLogoPriceTag() async {
    final path = await _pilihDanSimpanLogoLokal(
      subfolder: 'price_tag',
      namaFile: 'logo_price_tag',
    );
    if (path == null) return null;
    _priceTagLogoPath = path;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciPriceTagLogoPath, path);
    return path;
  }

  Future<void> hapusLogoPriceTag() async {
    final path = _priceTagLogoPath;
    _priceTagLogoPath = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kunciPriceTagLogoPath);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<String?> _pilihDanSimpanLogoLokal({
    required String subfolder,
    required String namaFile,
  }) async {
    final hasil = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: false,
    );
    final pathAsal = hasil?.files.single.path;
    if (pathAsal == null || pathAsal.trim().isEmpty) return null;

    final sumber = File(pathAsal);
    if (!await sumber.exists()) return null;

    final dir = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(dir.path, subfolder));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final ext = p.extension(pathAsal).toLowerCase();
    final targetPath = p.join(targetDir.path, '$namaFile$ext');
    final target = await sumber.copy(targetPath);
    return target.path;
  }

  Future<void> simpanTampilanLogo({
    required String mode,
    required double skala,
  }) async {
    _logoMode = mode == 'landscape' ? 'landscape' : 'persegi';
    _logoSkala = skala.clamp(0.8, 1.8);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciLogoMode, _logoMode);
    await sp.setDouble(_kunciLogoSkala, _logoSkala);
  }

  Future<void> simpanLebarKertas(double lebarMm) async {
    _lebarKertasMm = _normalisasiLebarKertas(lebarMm);
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kunciLebarKertasMm, _lebarKertasMm);
  }

  Future<void> simpanMarginKotakPriceTag(double marginMm) async {
    _priceTagMarginKotakMm = _normalisasiMarginPriceTag(marginMm);
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kunciPriceTagMarginKotakMm, _priceTagMarginKotakMm);
  }

  static double _normalisasiLebarKertas(double lebarMm) {
    return opsiLebarKertasMm.contains(lebarMm) ? lebarMm : 80;
  }

  static double _normalisasiMarginPriceTag(double marginMm) {
    return marginMm.clamp(0, 8).toDouble();
  }
}
