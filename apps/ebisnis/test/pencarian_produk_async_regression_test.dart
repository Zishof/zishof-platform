import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rapat(String path) {
  return File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
}

void main() {
  test('kasir apotik menolak hasil dan error pencarian yang sudah usang', () {
    final sumber = _rapat('lib/screens/apotik/kasir_apotik_screen.dart');

    expect(sumber, contains('finalgenerasi=++_generasiCari'));
    expect(sumber, contains('generasi==_generasiCari&&_cari.text.trim()'));
    expect(sumber, contains('mounted&&generasi==_generasiCari'));
    expect(sumber, contains('_mencari=false'));
  });

  test('dialog pencarian penjualan sales menolak respons usang', () {
    final sumber =
        _rapat('lib/screens/inventory_sales/penjualan_sales_screen.dart');

    expect(sumber, contains('finalgenerasi=++_generasiCari'));
    expect(sumber, contains('if(generasi==_generasiCari)'));
  });

  test('dialog pencarian SPJ menolak respons usang', () {
    final sumber = _rapat('lib/screens/inventory_sales/spj_screen.dart');

    expect(sumber, contains('finalgenerasi=++_generasiCari'));
    expect(sumber, contains('if(generasi==_generasiCari)'));
  });
}
