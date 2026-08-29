import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/price_tag_screen.dart').readAsStringSync();

  test('opsi barcode membedakan gambar pindai dari nomor teks', () {
    expect(source, contains('Tampilkan Barcode (Bisa Dipindai)'));
    expect(source, contains('Mencetak garis barcode dan angkanya'));
    expect(source, contains('Tampilkan Nomor Barcode Saja'));
    expect(source, contains('Hanya mencetak angka tanpa garis barcode'));
    expect(source, contains('Hasil saat ini hanya berupa angka barcode'));
  });

  test('PDF tetap membuat barcode Code 128 dari barcode atau kode produk', () {
    expect(source, contains('bc.Barcode.code128()'));
    expect(source, contains('final barcode = _kodeBarcode(p);'));
    expect(
        source, contains(r"final barcode = '${p['barcode'] ?? ''}'.trim();"));
    expect(source, contains(r"return '${p['kode'] ?? ''}'.trim();"));
  });
}
