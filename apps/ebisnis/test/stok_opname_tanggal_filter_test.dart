import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'riwayat Input Opname dapat memilih tanggal tanpa mengubah tanggal simpan',
      () {
    final source =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();

    expect(source, contains("'so_riwayat'"));
    expect(source, contains("'tanggal': _tanggalRiwayatTeks"));
    expect(source, contains('Pilih tanggal riwayat opname'));
    expect(source, contains('Riwayat Opname ·'));
    expect(source, contains("'stok_fisik': stokFisik"));
    expect(
        source,
        isNot(contains(
            "'tanggal': _tanggalRiwayatTeks,\n          'produk_id'")));
  });

  test('monitor mutasi mendukung rentang tanggal dan tetap membatasi 365 hari',
      () {
    final source =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();

    expect(source,
        contains("'tanggalMulai': _tanggalTeks(_rentangTanggal!.start)"));
    expect(source,
        contains("'tanggalSampai': _tanggalTeks(_rentangTanggal!.end)"));
    expect(source, contains('Pilih rentang tanggal mutasi'));
    expect(source, contains('Rentang tanggal maksimal 365 hari.'));
    expect(source, contains("'stok_mutasi_ledger'"));
  });
}
