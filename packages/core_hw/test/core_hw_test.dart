import 'package:flutter_test/flutter_test.dart';

import 'package:core_hw/core_hw.dart';

void main() {
  test('BarcodeScannerScreen default title', () {
    const w = BarcodeScannerScreen();
    expect(w.judul, 'Scan Barcode');
  });
}
