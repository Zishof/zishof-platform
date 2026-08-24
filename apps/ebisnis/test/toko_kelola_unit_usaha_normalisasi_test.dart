import 'package:ebisnis/screens/toko_kelola_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unit usaha mendukung respons objek dan string lintas versi', () {
    expect(
      normalisasiUnitUsahaToko([
        {'kode': 'apotik', 'label': 'Apotek'},
        'inventory',
        {'nama': 'eMedik'},
        'inventory',
        null,
      ]),
      [
        {'kode': 'apotik', 'label': 'Apotek'},
        {'kode': 'inventory', 'label': 'inventory'},
        {'kode': 'eMedik', 'label': 'eMedik'},
      ],
    );
  });

  test('nilai bukan daftar tidak menyebabkan cast exception', () {
    expect(normalisasiUnitUsahaToko(null), isEmpty);
    expect(normalisasiUnitUsahaToko('apotik'), isEmpty);
  });
}
