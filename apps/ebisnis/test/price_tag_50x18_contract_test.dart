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

  test('A4 potret 58 x 38 mm menghasilkan tiga kolom dengan margin standar 15 mm', () {
    expect(
      hitungJumlahLabelPadaSumbu(
        panjangTersediaMm: 180, // 210 - 15 - 15
        ukuranLabelMm: 58,
        jarakAntarLabelMm: 2,
      ),
      3,
    );
  });

  test('A4 potret 60 x 40 mm menghasilkan tiga kolom dengan margin 10 mm', () {
    expect(
      hitungJumlahLabelPadaSumbu(
        panjangTersediaMm: 190, // 210 - 10 - 10
        ukuranLabelMm: 60,
        jarakAntarLabelMm: 2,
      ),
      3,
    );
  });

  test('layout mendukung ukuran dan margin kertas fleksibel serta bantuan 3 kolom', () {
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
      'rak_58x38',
      'Atur 10 mm (3 Kolom)',
    ]) {
      expect(source, contains(marker), reason: 'kontrak hilang: $marker');
    }
  });
}
