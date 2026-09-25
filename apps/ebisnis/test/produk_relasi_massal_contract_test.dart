import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aksi massal resep dan custom menu memakai antrean local first', () {
    final layar = File('lib/screens/produk_screen.dart').readAsStringSync();
    expect(layar, contains('Aksi Massal Resep & Custom Menu'));
    expect(layar, contains("aksi: 'produk_relasi_massal'"));
    expect(layar, contains("'produk_ids': pilihan.toList()"));
    expect(layar, contains("'hapus_resep': hapusResep"));
    expect(layar, contains("'hapus_custom_menu': hapusCustom"));
    expect(layar, contains('prosesSimpanMaster(context'));
  });
}
