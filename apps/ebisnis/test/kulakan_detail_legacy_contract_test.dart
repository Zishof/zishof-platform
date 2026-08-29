import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail Kulakan menjaga audit faktur lama dan menampilkan solusi error',
      () {
    final source = File('lib/screens/kulakan_screen.dart').readAsStringSync();

    expect(
      source,
      contains("infoGalat(error, aktivitas: 'memuat detail faktur kulakan')"),
      reason:
          'Kegagalan detail harus membuka pesan edukatif beserta Informasi Teknis, bukan snackbar generik.',
    );
    expect(source, contains("header['peringatan']"));
    expect(source, contains("it['peringatan']"));
    expect(source, contains('_bukaRingkasanDetailTerbatas(f, e)'));
    expect(source, contains('Rincian item belum dapat dimuat'));
    expect(source, contains("'membuat faktur pengganti.'"));
  });
}
