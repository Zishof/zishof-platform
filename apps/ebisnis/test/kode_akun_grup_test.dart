import 'package:ebisnis/screens/kode_akun_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final daftar = <Map<String, dynamic>>[
    {'id': 4, 'nama': 'Aset Lancar'},
    {'id': 8, 'nama': 'Beban Operasional'},
  ];

  test('nama grup sama tidak dapat dibuat ulang dengan variasi huruf/spasi',
      () {
    expect(grupAkunNamaSudahDipakai(' aset   lancar ', daftar), isTrue);
  });

  test('grup yang sedang diedit boleh mempertahankan namanya', () {
    expect(
        grupAkunNamaSudahDipakai('ASET LANCAR', daftar, kecualiId: 4), isFalse);
  });

  test('nama grup baru yang berbeda tetap dapat digunakan', () {
    expect(grupAkunNamaSudahDipakai('Kas dan Bank', daftar), isFalse);
  });
}
