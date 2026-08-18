import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak wiring layar Kelola Toko terhadap API server (TokoApiHelper +
/// PosDemoProvisionHelper, SVN ^/src r77595/r77598): nama aksi, kunci payload
/// snake_case, token konfirmasi generator, dan batas 250..100000 per unit
/// usaha WAJIB persis. Pola test sama dgn grup_produk_kontrak_api_test.dart
/// (source-contract; ApiClient singleton tidak injectable utk widget test).
void main() {
  test('layar Kelola Toko memakai aksi dan parameter kontrak server', () {
    final source =
        File('lib/screens/toko_kelola_screen.dart').readAsStringSync();

    // CRUD: daftar (param cari), simpan (kunci snake_case), hapus.
    expect(source, contains("aksi('toko_kelola_list'"));
    expect(source, contains("'cari'"));
    expect(source, contains("aksi('toko_kelola_simpan'"));
    expect(source, contains("'boleh_melihat_toko_lain'"));
    expect(source, contains("'boleh_transaksi_stok_habis'"));
    expect(source, contains("'toko_demo'"));
    expect(source, contains("'unit_usaha'"));
    expect(source, contains("aksi('toko_kelola_hapus'"));

    // Katalog unit usaha utk checkbox ber-grup (form toko + popup generate).
    expect(source, contains("aksi('unit_usaha_katalog'"));

    // Generator per unit usaha: aksi + token konfirmasi + clamp klien =
    // clamp server (250..100000) + penanganan sinyal popup dari server.
    expect(source, contains("aksi('pos_demo_seed_products_unit_usaha'"));
    expect(source, contains("'SEED-DEMO-PRODUK-UNIT-USAHA'"));
    expect(source, contains('clamp(250, 100000)'));
    expect(source, contains("'perlu_pilih_unit_usaha'"));

    // Progres job latar di-poll lewat pos_demo_status (toko_id ikut dikirim).
    expect(source, contains("aksi('pos_demo_status'"));
    expect(source, contains("'toko_id'"));

    // Gerbang menu admin-only di kedua sisi navigasi (padanan gate server).
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    expect(drawer, contains("label: 'Kelola Toko'"));
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    expect(
        shell,
        contains(
            'if (kunci == MenuEBisnis.tokoKelola) return Sesi.instance.isAdmin;'));
  });
}
