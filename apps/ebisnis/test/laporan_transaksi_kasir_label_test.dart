import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nama kasir pada rincian laporan transaksi', () {
    test('mempertahankan nama yang dikirim pada baris transaksi', () {
      expect(
        labelKasirRincianTransaksi(
          kasirBaris: ' Ziko ',
          kasirFilter: 'Rizal',
        ),
        'Ziko',
      );
    });

    test('menggunakan kasir yang dipilih ketika rincian kosong', () {
      expect(
        labelKasirRincianTransaksi(
          kasirBaris: ' ',
          kasirFilter: 'Rizal',
        ),
        'Rizal',
      );
    });

    test('tidak menebak nama saat laporan semua kasir', () {
      expect(
        labelKasirRincianTransaksi(
          kasirBaris: null,
          kasirFilter: null,
        ),
        'Kasir tidak tercatat',
      );
    });
  });
}
