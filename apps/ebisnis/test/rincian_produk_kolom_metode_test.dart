import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Laporan Rincian Produk memuat kolom dan filter Metode Bayar', () {
    final file = File('lib/screens/laporan_transaksi_screen.dart');
    expect(file.existsSync(), isTrue);
    final isi = file.readAsStringSync();

    // 1. Filter metodeExact dan metode diteruskan
    expect(isi, contains("'metode': _metode.trim()"));
    expect(isi, contains("'metodeExact': _metode.trim()"));

    // 2. Kolom Metode ada di tabel rincian
    expect(isi, contains("AppTableColumn('Metode', flex: 3)"));
    expect(isi, contains("row['metode'] ?? '-'"));

    // 3. Kolom Metode ada di ekspor dynamic report (PDF / Excel / Word)
    expect(isi, contains("DynamicReportColumn('metode', 'Metode')"));

    // 4. Rincian dialog angka laporan memuat Metode
    expect(isi, contains("'Metode': '\${row['metode'] ?? '-'}'"));
  });
}
