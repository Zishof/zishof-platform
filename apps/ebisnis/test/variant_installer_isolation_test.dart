import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('helper update memakai folder sementara unik per pemasangan', () {
    final source =
        File('lib/services/pengaturan_update.dart').readAsStringSync();
    expect(source, contains("createTemp('pos-update-helper-')"));
  });

  test('installer Al-Bahjah dan Nahl memiliki identitas dan lokasi berbeda',
      () {
    final albahjah = File('installer/albahjah.iss').readAsStringSync();
    final nahl = File('installer/nahl.iss').readAsStringSync();
    for (final key in ['AppId', 'DefaultDirName', 'UninstallDisplayIcon']) {
      final pattern = RegExp('^$key=(.+)', multiLine: true);
      final a = pattern.firstMatch(albahjah)!.group(1);
      final n = pattern.firstMatch(nahl)!.group(1);
      expect(a, isNot(n), reason: key);
    }
    expect(albahjah, contains('Excludes: "ebisnis*.exe,abchicken.exe"'));
    expect(
        albahjah, contains('Release\\ebisnis_albahjah.exe"; DestDir: "{app}"'));
    expect(albahjah, isNot(contains('Release\\ebisnis_nahl.exe"')));
  });
}
