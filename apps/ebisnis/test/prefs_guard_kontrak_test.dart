import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak: SETIAP jalur boot wajib memanggil [PrefsGuard] sebelum apa pun
/// menyentuh SharedPreferences.
///
/// Ini menutup bug nyata: `main.dart` memanggilnya sejak awal, tetapi
/// `bootstrap.dart` — jalur bersama varian apotik, emedik, inventory_sales,
/// dan mitrainap — tidak. Satu file `shared_preferences.json` korup (mati
/// listrik saat menulis, atau proses dimatikan paksa di tengah tulis) membuat
/// `getInstance()` melempar; exception-nya ditelan `runZonedGuarded`, `runApp`
/// tidak pernah dipanggil, dan jendela dibuat TANPA PERNAH dirender —
/// aplikasi tampak tidak bisa dibuka sama sekali, tanpa pesan apa pun.
/// Dikonfirmasi di lapangan: build varian apotik menggantung persis begitu.
void main() {
  const jalurBoot = <String>[
    'lib/main.dart',
    'lib/bootstrap.dart',
  ];

  test('setiap jalur boot memanggil PrefsGuard sebelum runApp', () {
    for (final berkas in jalurBoot) {
      final source = File(berkas).readAsStringSync();
      final iGuard = source.indexOf('PrefsGuard.perbaikiJikaKorup(');
      expect(iGuard, greaterThanOrEqualTo(0),
          reason: '$berkas tidak memanggil PrefsGuard.perbaikiJikaKorup()');
      final iRunApp = source.indexOf('runApp(');
      expect(iRunApp, greaterThanOrEqualTo(0), reason: '$berkas tanpa runApp');
      expect(iGuard, lessThan(iRunApp),
          reason: '$berkas memanggil PrefsGuard setelah runApp — '
              'terlambat, preferensi sudah dibaca lebih dulu');
      // Dipanggil ber-await: kalau tidak, perbaikannya belum tentu selesai
      // saat SharedPreferences pertama kali dibaca.
      expect(source.substring(0, iGuard).endsWith('await '), isTrue,
          reason: '$berkas harus meng-await PrefsGuard.perbaikiJikaKorup()');
    }
  });

  test('entrypoint varian memang lewat bootstrap bersama', () {
    for (final berkas in const [
      'lib/main_apotik.dart',
      'lib/main_emedik.dart',
      'lib/main_inventory_sales.dart',
      'lib/main_mitrainap.dart',
    ]) {
      final source = File(berkas).readAsStringSync();
      expect(source, contains('bootstrap('),
          reason: '$berkas tidak lewat bootstrap bersama, jadi penjaga '
              'preferensi di sana tidak berlaku untuknya');
    }
  });
}
