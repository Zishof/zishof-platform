import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pipeline rilis menolak APK dengan sertifikat Android Debug', () {
    final verifier = File('tool/verify_apk_signing.ps1').readAsStringSync();
    final buildAll = File('tool/build_semua_varian.ps1').readAsStringSync();

    expect(verifier, contains('CN=Android Debug'));
    expect(verifier, contains(r'$AllowDebug'));
    expect(verifier, contains('throw @"'));
    expect(buildAll, contains('verify_apk_signing.ps1'));
    expect(buildAll, contains(r'$IzinkanDebugSigning'));
  });

  test('wrapper Al-Bahjah dan Nahl memakai verifier yang sama', () {
    for (final path in <String>[
      'tool/build_apk_albahjah.ps1',
      'tool/build_apk_nahl.ps1',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('verify_apk_signing.ps1'), reason: path);
      expect(source, contains(r'$IzinkanDebugSigning'), reason: path);
    }
  });

  test('pipeline rilis menolak installer Windows tanpa Authenticode', () {
    final verifier = File('tool/verify_windows_signing.ps1').readAsStringSync();
    final buildAll = File('tool/build_semua_varian.ps1').readAsStringSync();

    expect(verifier, contains('Get-AuthenticodeSignature'));
    expect(verifier, contains(r'$AllowUnsigned'));
    expect(verifier, contains('AIS_WINDOWS_SIGNING_THUMBPRINT'));
    expect(buildAll, contains('verify_windows_signing.ps1'));
    expect(buildAll, contains(r'$IzinkanUnsignedWindows'));
  });
}
