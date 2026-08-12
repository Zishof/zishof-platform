import 'package:core_db/core_db.dart';
import 'package:ebisnis/main.dart' as app;
import 'package:ebisnis/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('database baru terbuka dan pengguna dapat login', (tester) async {
    // Ini sengaja dijalankan sebelum UI. Pada APK lama baris ini melempar
    // DatabaseException Android karena PRAGMA result-set dipanggil melalui
    // execute(), sehingga pengujian ini menjadi regresi langsung untuk bug.
    final database = await CoreDb.instance.db;
    final quickCheck = await database.rawQuery('PRAGMA quick_check');
    expect(quickCheck.first.values.first, 'ok');

    app.main();
    await _tungguSampai(
      tester,
      () => find.byType(LoginScreen).evaluate().isNotEmpty,
      alasan: 'Layar login tidak tampil setelah inisialisasi database',
    );

    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    expect(username, isNotEmpty, reason: 'POS_TEST_USERNAME belum diberikan');
    expect(password, isNotEmpty, reason: 'POS_TEST_PASSWORD belum diberikan');

    await tester.enterText(
      find.widgetWithText(TextField, 'Username'),
      username,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      password,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Masuk'));

    await _tungguSampai(
      tester,
      () => find.byType(LoginScreen).evaluate().isEmpty,
      alasan: 'Login uji tidak berpindah ke halaman POS',
    );

    expect(find.textContaining('Gagal memuat data lokal'), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
  });
}

Future<void> _tungguSampai(
  WidgetTester tester,
  bool Function() kondisi, {
  required String alasan,
}) async {
  for (var detik = 0; detik < 60; detik++) {
    await tester.pump(const Duration(seconds: 1));
    if (kondisi()) return;
  }
  fail(alasan);
}
