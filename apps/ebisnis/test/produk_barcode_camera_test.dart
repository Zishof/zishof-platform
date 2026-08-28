import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('form produk menyediakan scan kamera barcode dan QR-Code', () {
    final source = File('lib/screens/produk_screen.dart').readAsStringSync();

    expect(source, contains("import 'package:core_hw/core_hw.dart';"));
    expect(source, contains('BarcodeScannerScreen.pindai('));
    expect(source, contains("judul: 'Scan Barcode / QR-Code Produk'"));
    expect(source, contains('icon: const Icon(Icons.qr_code_scanner)'));
    expect(source, contains('_barcode.text = hasil.trim();'));
  });
}
