import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu HRD memakai kontrak API Pegawai Cuti dan Kehadiran', () {
    final layar = File('lib/screens/hrd_dasar_screen.dart').readAsStringSync();
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();

    for (final aksi in const [
      'hrd_pegawai_daftar',
      'hrd_jenis_cuti_daftar',
      'hrd_cuti_daftar',
      'hrd_cuti_simpan',
      'hrd_cuti_putusan',
      'hrd_kehadiran_daftar',
    ]) {
      expect(layar, contains("'$aksi'"));
    }
    expect(shell, contains('MenuEBisnis.hrdDasar'));
    expect(shell, contains("MenuEBisnis.hrdDasar: 'hrd_dasar'"));
    expect(shell, contains("_GrupMenuShell('SDM'"));
  });
}
