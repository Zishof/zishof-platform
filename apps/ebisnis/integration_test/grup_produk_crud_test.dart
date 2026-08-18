import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/grup_produk_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// UAT runtime layar Grup Produk terhadap SERVER SUNGGUHAN (bukan mock):
/// Dart widget -> ApiClient -> PosApi/Api_eBisnis -> Hibernate -> PostgreSQL.
/// Dijalankan di device `windows` (= UAT POS Desktop) dan dapat diulang di
/// emulator/perangkat Android (= UAT POS Android) tanpa perubahan apa pun.
///
/// Wajib diberi kredensial + alamat server lewat dart-define (pola sama
/// android_startup_login_test.dart):
///   flutter test integration_test/grup_produk_crud_test.dart -d windows \
///     --dart-define=POS_TEST_USERNAME=... --dart-define=POS_TEST_PASSWORD=... \
///     --dart-define=POS_TEST_HOST=localhost:18080 \
///     --dart-define=POS_TEST_CONTEXT=ais --dart-define=POS_TEST_HTTPS=false
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('siklus CRUD Grup Produk end-to-end terhadap server nyata',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const https =
        String.fromEnvironment('POS_TEST_HTTPS', defaultValue: 'true');
    expect(username, isNotEmpty, reason: 'POS_TEST_USERNAME belum diberikan');
    expect(password, isNotEmpty, reason: 'POS_TEST_PASSWORD belum diberikan');
    expect(host, isNotEmpty, reason: 'POS_TEST_HOST belum diberikan');

    // Arahkan ApiClient ke server uji, lalu login sungguhan (token Bearer).
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: https == 'true');
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Integration-GrupProduk',
    });
    expect(login['token'], isNotNull, reason: 'Login uji gagal: $login');
    await ApiClient.instance.simpanToken(login['token'] as String);

    const namaGrup = 'Grup UAT Flutter';

    // ---- Muat layar; daftar awal harus termuat (kosong / tanpa grup uji) ----
    await tester.pumpWidget(const MaterialApp(home: GrupProdukScreen()));
    await _tungguSampai(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      alasan: 'Daftar Grup Produk tidak selesai dimuat',
    );
    expect(find.text(namaGrup), findsNothing,
        reason: 'Sisa data uji sebelumnya masih ada -- bersihkan dulu');

    // ---- Tambah ----
    await tester.tap(find.text('Tambah Grup'));
    await _tungguSampai(
      tester,
      () => find.text('Tambah Grup Produk').evaluate().isNotEmpty,
      alasan: 'Dialog Tambah Grup tidak terbuka',
    );
    await tester.enterText(
        find.widgetWithText(TextField, 'Kode Grup'), 'FLT-UAT');
    await tester.enterText(
        find.widgetWithText(TextField, 'Nama Grup *'), namaGrup);
    await tester.enterText(
        find.widgetWithText(TextField, 'HPP / Harga Beli'), '17000');
    await tester.enterText(
        find.widgetWithText(TextField, 'Harga Jual'), '28000');
    await tester.tap(find.text('Simpan & Terapkan'));
    await _tungguSampai(
      tester,
      () =>
          find.textContaining(namaGrup).evaluate().isNotEmpty &&
          find.text('Tambah Grup Produk').evaluate().isEmpty,
      alasan: 'Grup baru tidak muncul di daftar setelah disimpan',
    );

    // ---- Ubah (round-trip nilai + update harga) ----
    await tester.tap(find.byTooltip('Ubah & terapkan harga').first);
    await _tungguSampai(
      tester,
      () => find.text('Ubah Grup Produk').evaluate().isNotEmpty,
      alasan: 'Dialog Ubah tidak terbuka',
    );
    expect(
        (tester
                .widget<TextField>(
                    find.widgetWithText(TextField, 'Nama Grup *'))
                .controller!)
            .text,
        namaGrup,
        reason: 'Round-trip: nama tersimpan tidak terisi ulang di form');
    await tester.enterText(
        find.widgetWithText(TextField, 'Harga Jual'), '29000');
    await tester.tap(find.text('Simpan & Terapkan'));
    await _tungguSampai(
      tester,
      () => find.text('Ubah Grup Produk').evaluate().isEmpty,
      alasan: 'Dialog Ubah tidak menutup setelah simpan',
    );
    await _tungguSampai(
      tester,
      () => find.textContaining('29.000').evaluate().isNotEmpty,
      alasan: 'Harga jual baru (29.000) tidak tampil di daftar',
    );

    // ---- Hapus (grup tanpa anggota harus langsung terhapus) ----
    await tester.tap(find.byTooltip('Hapus').first);
    await _tungguSampai(
      tester,
      () => find.text('Hapus Grup Produk').evaluate().isNotEmpty,
      alasan: 'Dialog konfirmasi hapus tidak terbuka',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await _tungguSampai(
      tester,
      () => find.textContaining(namaGrup).evaluate().isEmpty,
      alasan: 'Grup uji masih tampil setelah dihapus',
    );

    // Bersih: server tidak lagi memuat grup uji.
    final akhir = await ApiClient.instance
        .aksi('grup_produk_daftar', {'hanya_aktif': false});
    final sisa = (akhir['data'] as List? ?? [])
        .where((g) => (g as Map)['nama'] == namaGrup);
    expect(sisa, isEmpty, reason: 'Grup uji masih ada di server');
  });
}

Future<void> _tungguSampai(
  WidgetTester tester,
  bool Function() kondisi, {
  required String alasan,
}) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (kondisi()) return;
  }
  fail(alasan);
}
