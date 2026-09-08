import 'package:ebisnis/screens/kulakan_bulk_entry_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('total HPP per baris Bulk Entry Kulakan', () {
    test('mengalikan qty dengan harga beli', () {
      expect(
        hitungTotalHppBaris(
          qty: 6,
          hargaBeli: 20500,
          diskon: 0,
          ppn: 0,
        ),
        123000,
      );
    });

    test('mengurangi diskon dan menambahkan PPN nominal', () {
      expect(
        hitungTotalHppBaris(
          qty: 10,
          hargaBeli: 10000,
          diskon: 5000,
          ppn: 10450,
        ),
        105450,
      );
    });

    test('tetap nol untuk baris kosong', () {
      expect(
        hitungTotalHppBaris(
          qty: 0,
          hargaBeli: 0,
          diskon: 0,
          ppn: 0,
        ),
        0,
      );
    });
  });
}
