import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tabel master produk menampilkan HPP di samping harga jual', () {
    final source = File('lib/screens/produk_screen.dart').readAsStringSync();

    final hpp = source.indexOf("Text('HPP'");
    final hargaJual = source.indexOf("Text('HARGA JUAL'");
    expect(hpp, greaterThanOrEqualTo(0));
    expect(hargaJual, greaterThan(hpp));
    expect(source, contains('_formatRupiah.format(produk.hargaBeli)'));
  });

  test('faktur pembelian memakai A4 potret dan preview sebelum print', () {
    final source = File('lib/screens/kulakan_screen.dart').readAsStringSync();

    expect(source, contains('pageFormat: PdfPageFormat.a4.portrait'));
    expect(source, contains("label: const Text('Pratinjau & Print')"));
    expect(source, contains('await tampilkanPratinjauPdf('));
    expect(source, isNot(contains('pageFormat: PdfPageFormat.a4.landscape')));
    expect(source, isNot(contains('await Printing.layoutPdf(')));
  });
}
