import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/produk_screen.dart').readAsStringSync();

  test('kartu statistik memuat stok minus dan seluruh kartu clickable', () {
    expect(source, contains("'Stok Minus'"));
    expect(source, contains(r"'Halaman ${_halaman + 1} dari $_jumlahHalaman'"));
    expect(source, contains('initialFirstRowIndex:'));
    expect(source, contains('onPageChanged:'));
    expect(source, contains("'stokMinus'"));
    expect(source, contains('onTap: () => onTap(tipe, label)'));
    expect(source, contains("tooltip: 'Lihat daftar produk \$label'"));
  });

  test('detail statistik menampilkan seluruh kolom operasional produk', () {
    for (final label in const [
      'Kode',
      'Barcode',
      'Nama',
      'Harga Jual',
      'Harga Beli',
      'Stok',
      'Stok Minimal',
      'Terakhir Pengadaan',
      'Keterangan',
    ]) {
      expect(source, contains("Text('$label')"), reason: label);
    }
    expect(source, contains("row['alasanStok']"));
  });

  test('detail statistik dapat dicetak PDF dan diunduh sebagai Excel', () {
    expect(source, contains("const Text('Cetak PDF')"));
    expect(source, contains("const Text('Download Excel')"));
    expect(source, contains('DynamicReportDesigner.exportPdf'));
    expect(source, contains('DynamicReportDesigner.exportExcel'));
  });
}
