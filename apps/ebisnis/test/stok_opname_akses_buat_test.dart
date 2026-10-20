import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('input stok opname mengikuti izin create yang juga diperiksa server',
      () {
    final source = File('lib/screens/stok_opname_screen.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');

    expect(
        source, contains("Sesi.instance.bolehAksiPos('stokopname', 'create')"));
    expect(source, isNot(contains('if (!Sesi.instance.bolehKelola)')));
    expect(source, contains('Stok Opname: Buat'));
    expect(
        source,
        contains(
            "Sesi.instance.bolehAksiPos('stokopname', 'delete')"));
    expect(source, contains('final bolehUnggah ='));
    expect(source, contains("bolehAksiPos('stokopname', 'create')"));
    expect(source, contains('AksiBarisMenu'));
  });
}
