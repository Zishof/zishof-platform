import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cetak struk Windows fallback ke dialog PDF bila printer tidak aktif',
      () {
    final struk = File('lib/screens/struk_screen.dart').readAsStringSync();
    final printUtil = File('lib/services/print_util.dart').readAsStringSync();

    expect(struk, contains('printerKasirAktifTerdeteksi('));
    expect(
      struk,
      contains(
          "throw Exception('Tidak ada printer struk aktif yang terdeteksi.')"),
    );
    expect(struk, contains('_cetakStrukPdfViaDialogOs()'));
    expect(struk, contains('cetakPdfDenganDialogOs('));

    expect(printUtil, contains('Future<void> cetakPdfDenganDialogOs'));
    expect(printUtil, contains('Printing.layoutPdf('));
    expect(printUtil, contains('_printerEksporPdfSistem'));
  });
}
