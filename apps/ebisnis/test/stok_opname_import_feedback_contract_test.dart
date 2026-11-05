import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unggah opname menjelaskan baris yang dilewati tanpa rincian server',
      () {
    final source =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();

    expect(source, contains('if (dilewati > 0)'));
    expect(source, contains('Rincian penyebab belum tersedia'));
    expect(source, contains('kolom Stok Fisik sudah diisi'));
    expect(source, contains('berasal dari toko yang sedang dipilih'));
  });

  test(
      'unggah ulang mengingatkan pemeriksaan riwayat untuk mencegah catatan ganda',
      () {
    final source =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();

    expect(source, contains('periksa Riwayat Opname'));
    expect(source, contains('unggah hanya baris yang belum tersimpan'));
    expect(source, contains('impor massal online-only'));
  });

  test('aksi menutup rincian tersedia lewat menu tiga titik', () {
    final source =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();

    expect(source, contains("tooltip: 'Aksi hasil unggah'"));
    expect(source, contains("label: 'Tutup'"));
    expect(source, contains('AksiBarisMenu('));
  });
}
