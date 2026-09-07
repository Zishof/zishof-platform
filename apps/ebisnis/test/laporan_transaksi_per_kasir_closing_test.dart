import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regresi laporan Transaksi Per Kasir:
/// kasClosing=0 tanpa closing terkonfirmasi bukan uang fisik nol dan tidak
/// boleh ditampilkan sebagai selisih minus.
void main() {
  late String source;

  setUpAll(() {
    source =
        File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync();
  });

  test('total selisih hanya menjumlahkan closing terkonfirmasi', () {
    expect(source, contains("row['closingDikonfirmasi'] == true"));
    expect(source,
        contains(".where((row) => row['closingDikonfirmasi'] == true)"));
    expect(source, contains('Total selisih sesi tertutup'));
  });

  test('kasir tanpa closing tidak ditampilkan sebagai minus', () {
    expect(source, contains("'Belum closing'"));
    expect(source, contains("'Belum dicatat'"));
    expect(source, contains("'Belum dapat dihitung'"));
    expect(source, contains('Kas closing Rp0 pada kondisi ini bukan berarti'));
  });

  test('ekspor membedakan angka closing dari status belum closing', () {
    expect(source, contains("'statusClosing':"));
    expect(source, contains("'kasClosingLaporan':"));
    expect(source, contains("'selisihLaporan':"));
    expect(source,
        contains("DynamicReportColumn('statusClosing', 'Status Closing')"));
  });
}
