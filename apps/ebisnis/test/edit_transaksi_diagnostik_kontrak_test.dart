import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail riwayat menjelaskan alasan tombol edit tidak tersedia', () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();
    expect(source, contains("hasil['alasanEditTransaksi']"));
    expect(source, contains("hasil['bolehEditTransaksi'] != true"));
  });
}
