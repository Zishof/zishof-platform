import 'package:ebisnis/screens/struk_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('identitas kasir pada struk', () {
    test('cetak ulang memakai kasir pada transaksi asal', () {
      expect(
        labelKasirStruk(
          cetakUlang: true,
          kasirTransaksi: ' Ziko ',
          kasirAktif: 'ika',
        ),
        'Ziko',
      );
    });

    test('cetak ulang tidak menebak kasir dari akun yang sedang aktif', () {
      expect(
        labelKasirStruk(
          cetakUlang: true,
          kasirTransaksi: null,
          kasirAktif: 'ika',
        ),
        'Kasir tidak tercatat',
      );
    });

    test('struk transaksi baru tetap memakai akun kasir aktif', () {
      expect(
        labelKasirStruk(
          cetakUlang: false,
          kasirTransaksi: 'Kasir sebelumnya',
          kasirAktif: 'ika',
        ),
        'ika',
      );
    });
  });
}
