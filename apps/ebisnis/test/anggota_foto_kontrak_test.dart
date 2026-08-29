import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('form member menyediakan foto galeri, kamera, hapus, dan antre offline',
      () {
    final source =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    expect(source, contains("'anggota_foto_upload'"));
    expect(source, contains("'anggota_foto_hapus'"));
    expect(source, contains('FotoProdukCameraScreen.ambil'));
    expect(source, contains('ImageSource.gallery'));
    expect(source, contains('kompresGambarKeBawah500Kb'));
    expect(source, contains('prosesSimpanMaster(context'));
    expect(source, contains('headerTrailing: _avatarHeader()'));
  });
}
