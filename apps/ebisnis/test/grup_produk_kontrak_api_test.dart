import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak wiring layar Grup Produk terhadap API server (GrupProdukApiHelper,
/// SVN ^/src r77580): nama aksi dan parameter WAJIB persis -- regresi nama
/// aksi (mis. grup_produk_list vs grup_produk_daftar) pernah terjadi dan
/// membuat daftar gagal dimuat diam-diam. Pola test sama dgn
/// apotik_data_contoh_button_test.dart (source-contract; ApiClient singleton
/// tidak injectable utk widget test ber-mock).
void main() {
  test('layar Grup Produk memakai aksi dan parameter kontrak server', () {
    final source =
        File('lib/screens/grup_produk_screen.dart').readAsStringSync();

    // Daftar: nama aksi kanonis + parameter hanya_aktif (bukan termasuk_nonaktif).
    // Sejak offline-first master, panggilan lewat MasterOffline (bukan
    // ApiClient langsung) -- nama aksinya tetap terkunci di sini.
    expect(source, contains("'grup_produk_daftar'"));
    expect(source, contains("'hanya_aktif': false"));
    expect(source, isNot(contains('grup_produk_list')));
    expect(source, isNot(contains('termasuk_nonaktif')));

    // Simpan: satu aksi utk tambah/ubah + kunci payload snake_case milik server.
    expect(source, contains("'grup_produk_simpan'"));
    expect(source, contains("'harga_beli'"));
    expect(source, contains("'harga_jual'"));

    // Hapus ber-konfirmasi; server menolak grup yang masih dipakai produk.
    expect(source, contains("'grup_produk_hapus'"));

    // Gerbang menu fail-closed di drawer (kunci grup_produk, KUNCI_DEFAULT_NONAKTIF).
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    expect(drawer, contains("bolehMenuVarianBaru('grup_produk')"));
  });
}
