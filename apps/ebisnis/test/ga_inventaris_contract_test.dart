import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inventaris GA memakai kontrak tenant dan menu fail closed', () {
    final layar =
        File('lib/screens/ga_inventaris_screen.dart').readAsStringSync();
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    for (final aksi in [
      'ga_inventaris_daftar',
      'ga_inventaris_referensi',
      'ga_inventaris_simpan',
      'ga_inventaris_ubah'
    ]) {
      expect(layar, contains("'$aksi'"));
    }
    expect(shell, contains("MenuEBisnis.gaInventaris: 'ga_inventaris'"));
    expect(shell, contains("_GrupMenuShell('General Affair'"));
  });
}
