import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final screen = File('lib/screens/abchicken/operasi_abchicken_screen.dart')
      .readAsStringSync();
  final variant = File('lib/app_variant.dart').readAsStringSync();
  final setting = File('lib/app_setting.dart').readAsStringSync();
  final serverConfig =
      File('lib/services/server_config.dart').readAsStringSync();
  final profile = File('lib/product_profile.dart').readAsStringSync();

  test('varian AB Chicken memakai identitas dan endpoint produksi yang benar',
      () {
    expect(variant, contains("kode == 'abchicken'"));
    expect(setting, contains("'abchiken.ebisnis.id'"),
        reason: 'Ejaan domain produksi memang abchiken, bukan kode brand.');
    expect(serverConfig, contains('if (AppVariant.isAbChicken)'));
    expect(serverConfig,
        contains('AppVariant.isAbChicken ? AppSetting.baseUrlHost : host'));
    expect(profile, contains('AppProductProfile.abChicken'));
    expect(profile, contains('OperasiRantaiPasokScreen'));
  });

  test('semua daftar operasi membaca cache lebih dahulu dan dipaginasi 50', () {
    expect(screen, contains('MasterOffline.daftarCacheDulu('));
    expect(screen, contains("'batas': _batas"));
    expect(screen, contains('static const _batas = 50'));
    expect(screen, contains("'abchicken:\$_proses'"));
  });

  test('posting dan approval tetap online-only dengan pesan sumber akun', () {
    expect(screen, contains('// Online-only:'));
    expect(screen, contains(".aksi('si_restaurant_\${_proses}_post'"));
    expect(screen, contains(".aksi('si_restaurant_\${_proses}_status'"));
    expect(screen, contains('akun pendapatan dan HPP dari Master Produk'));
    expect(screen, contains('Sumber Akun Posting'));
  });

  test('layar membedakan record sudah dan belum diposting', () {
    expect(screen, contains("'TELAH DIPOSTING'"));
    expect(screen, contains("'BELUM DIPOSTING'"));
    expect(screen, contains("row['sudahPosting'] == true"));
    expect(screen, contains("'Telah diposting' : 'Belum diposting'"));
  });

  test('penjualan POS membentuk jurnal dan HPP berbasis BOM', () {
    expect(screen, contains("'pos_sale', 'Penjualan POS'"));
    expect(screen, contains("_proses == 'pos_sale'"));
    expect(screen, contains("s == 'DRAF' || s == 'TERPOSTING'"));
    expect(screen, contains('akun persediaan bahan dari BOM'));
  });
}
