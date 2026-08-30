import 'dart:io';

import 'package:ebisnis/screens/price_tag_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/price_tag_screen.dart').readAsStringSync();

  test('stiker produk menyediakan preset 50 x 18 mm', () {
    expect(source, contains("id: 'produk_50x18'"));
    expect(source, contains('lebarMm: 50'));
    expect(source, contains('tinggiMm: 18'));
  });

  test('A4 potret 50 x 18 mm menghasilkan tiga kolom label', () {
    expect(
      hitungJumlahLabelPadaSumbu(
        panjangTersediaMm: 200,
        ukuranLabelMm: 50,
        jarakAntarLabelMm: 2,
      ),
      3,
    );
  });

  test('layout mendukung ukuran dan margin kertas fleksibel', () {
    for (final marker in const [
      'Ukuran Stiker Kustom',
      'Lebar kertas',
      'Tinggi kertas',
      'Atas / header',
      'Orientasi Kertas',
      'marginKiriMm',
      'marginAtasMm',
      'marginKananMm',
      'marginBawahMm',
    ]) {
      expect(source, contains(marker), reason: 'kontrak hilang: $marker');
    }
  });
}
