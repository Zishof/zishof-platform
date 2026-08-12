import 'package:ebisnis/screens/bantuan_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setiap panduan platform berisi minimal 1000 kata', () {
    expect(artikelBantuan, hasLength(3));
    for (final artikel in artikelBantuan) {
      expect(
        artikel.jumlahKata,
        greaterThanOrEqualTo(1000),
        reason: '${artikel.judul} hanya ${artikel.jumlahKata} kata',
      );
    }
  });

  test('setiap panduan mempunyai struktur operasional lengkap', () {
    for (final artikel in artikelBantuan) {
      expect(artikel.bagian.length, greaterThanOrEqualTo(10));
      expect(artikel.ringkasan, isNotEmpty);
    }
  });
}
