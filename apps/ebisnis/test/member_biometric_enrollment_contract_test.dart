import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('form member menyediakan lima slot fingerprint dan lima wajah', () {
    final source = File('lib/screens/anggota/member_biometric_panel.dart')
        .readAsStringSync();
    for (final slot in const [
      'JEMPOL_KANAN',
      'TELUNJUK_KANAN',
      'JEMPOL_KIRI',
      'TELUNJUK_KIRI',
      'JARI_CADANGAN',
      'WAJAH_DEPAN_1',
      'WAJAH_DEPAN_2',
      'WAJAH_KIRI',
      'WAJAH_KANAN',
      'WAJAH_CADANGAN',
    ]) {
      expect(source, contains("'$slot'"));
    }
  });

  test('template hanya dikirim ke API biometrik dan tidak diekspor', () {
    final source = File('lib/screens/anggota/member_biometric_panel.dart')
        .readAsStringSync();
    expect(source, contains("aksi('biometrik_daftar'"));
    expect(source, contains("aksi('biometrik_kemampuan'"));
    expect(source, contains("aksi('biometrik_simpan'"));
    expect(source, contains("aksi('biometrik_nonaktifkan'"));
    expect(source, contains("'template_base64': sample.templateBase64"));
    expect(source, isNot(contains('Download template')));
    expect(source, isNot(contains('Export biometrik')));
    expect(source, contains('enrollmentReady(modality)'));
    expect(source, contains('Diagnostik kesiapan biometrik'));
    expect(source, contains('_readiness.diagnostics(modality)'));
  });

  test('form member memasang panel hanya setelah user id tersedia', () {
    final source =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    expect(source, contains('MemberBiometricPanel('));
    expect(source, contains('_userid.text.trim().isNotEmpty'));
  });

  test('Android menolak biometrik member sampai SDK vendor tersedia', () {
    final source = File(
      'android/app/src/main/kotlin/id/zishof/ebisnis/MainActivity.kt',
    ).readAsStringSync();
    expect(source, contains('ais_mobile/biometric_capture'));
    expect(source, contains('"fingerprint" to false'));
    expect(source, contains('"face" to false'));
    expect(source, contains('BIOMETRIC_VENDOR_SDK_REQUIRED'));
    expect(source, contains('BiometricPrompt bawaan tidak digunakan'));
  });
}
