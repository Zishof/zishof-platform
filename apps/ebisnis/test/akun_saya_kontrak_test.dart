import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ganti password mengirim konfirmasi dan mempertahankan detail galat',
      () {
    final source = File('lib/screens/akun_saya_screen.dart').readAsStringSync();

    expect(source, contains("'password_lama': _lamaController.text"));
    expect(source, contains("'password_baru': _baruController.text"));
    expect(
        source, contains("'konfirmasi_password': _konfirmasiController.text"));
    expect(source, contains('e is ApiException ? e.info : e'));
    expect(source, contains("aktivitas: 'mengganti kata sandi'"));
    expect(source, isNot(contains("Text('Gagal: \$e')")));
  });
}
