import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/main.dart' as app;
import 'package:ebisnis/product_profile.dart';
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:ebisnis/screens/login_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR',
    defaultValue:
        r'C:\opt\AIS\ais\src\main\docs\pos\manual-uat-pengadaan-volume\screenshots-uat');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT bergambar Pengadaan volume termin dan non-termin',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final oldError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldError);
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const tokenTersimpan = String.fromEnvironment('POS_TEST_TOKEN');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    if (tokenTersimpan.isNotEmpty) {
      await ApiClient.instance.simpanToken(tokenTersimpan);
    } else {
      Map<String, dynamic>? login;
      Object? loginError;
      for (var attempt = 1; attempt <= 4 && login == null; attempt++) {
        try {
          login = await ApiClient.instance.aksi('login', {
            'username': username,
            'password': password,
            'labelPerangkat': 'UAT-Manual-Pengadaan-Volume',
          });
        } catch (e) {
          loginError = e;
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
      if (login == null) throw StateError('Login UAT gagal: $loginError');
      await ApiClient.instance.simpanToken(login['token'] as String);
    }
    AppProductProfile.aktif = const AppProductProfile.apotik();
    app.main();
    await _wait(tester, () => find.byType(KasirScreen).evaluate().isNotEmpty,
        reason: 'Layar POS belum siap', seconds: 180);
    FlutterError.onError = (detail) {
      if (detail.exceptionAsString().contains('A RenderFlex overflowed')) {
        // ignore: avoid_print
        print('UAT_LAYOUT_OVERFLOW=${detail.exceptionAsString()}');
        return;
      }
      oldError?.call(detail);
    };
    expect(find.byType(LoginScreen), findsNothing);
    // Instalasi/test runner baru dapat menampilkan dialog sinkronisasi awal.
    // Tutup secara eksplisit agar bukti dan interaksi berikutnya merekam layar
    // Pengadaan, bukan modal onboarding yang menutup tombol aksi.
    await _tutupOnboardingJikaAda(tester);
    await _shot(tester, '00-layar-awal-ebisnis');

    await _tapSidebar(tester, 'PENGADAAN');
    await _shot(tester, '01-menu-pengadaan-terbuka');

    await _openMenu(tester, 'Permintaan Pembelian (PR)');
    await _shot(tester, '02-pr-daftar-50');
    await tester.tap(find.text('Buat PR').last);
    await _wait(tester,
        () => find.text('Buat Permintaan Pembelian').evaluate().isNotEmpty,
        reason: 'Form PR tidak terbuka');
    await _shot(tester, '03-pr-formulir');
    await tester.tap(find.text('Batal').last);
    await tester.pump(const Duration(milliseconds: 500));

    await _openMenu(tester, 'Pemesanan Pembelian (PO)');
    await _shot(tester, '04-po-daftar-termin-nontermin');
    await tester.tap(find.text('Buat PO').last);
    await _wait(tester,
        () => find.text('Buat Pemesanan Pembelian').evaluate().isNotEmpty,
        reason: 'Form PO tidak terbuka');
    await _shot(tester, '05-po-formulir-nontermin');
    if (find.text('Pembayaran bertermin').evaluate().isNotEmpty) {
      await tester.tap(find.text('Pembayaran bertermin').last);
      await tester.pump(const Duration(milliseconds: 500));
      await _shot(tester, '06-po-formulir-termin');
    }
    await tester.tap(find.text('Batal').last);
    await tester.pump(const Duration(milliseconds: 500));

    await _openMenu(tester, 'Penerimaan Barang (BAST)');
    await _shot(tester, '07-bast-daftar-50');
    // Tombol dapat berubah menjadi kartu RichText setelah data dasbor selesai
    // dimuat. Dialog pemilih hanya pelengkap dokumentasi; daftar BAST tetap harus
    // direkam dan langkah berikutnya tidak boleh gagal bila tombol tidak tappable.
    final dariPo = find.textContaining('Dari PO');
    if (dariPo.evaluate().isNotEmpty) {
      await tester.tap(dariPo.first, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 1));
      if (find.textContaining('Pilih').evaluate().isNotEmpty) {
        await _shot(tester, '08-bast-pilih-po');
        final tutup = find.text('Batal').evaluate().isNotEmpty
            ? find.text('Batal')
            : find.text('Tutup');
        if (tutup.evaluate().isNotEmpty) {
          await tester.tap(tutup.last, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 500));
        }
      }
    }

    await _openMenu(tester, 'Terima Tagihan Vendor');
    await _shot(tester, '09-terima-tagihan-50');

    await _tapSidebar(tester, 'KEUANGAN');
    await _openMenu(tester, 'Proses Transfer');
    if (find.text('Pembayaran Vendor').evaluate().isNotEmpty) {
      await tester.tap(find.text('Pembayaran Vendor').last);
      await tester.pump(const Duration(seconds: 1));
    }
    await _waitNoSpinner(tester, seconds: 90);
    await _shot(tester, '10-pembayaran-vendor-50');

    await _tapSidebar(tester, 'AKUNTANSI');
    await _openMenu(tester, 'Draft Jurnal');
    await _shot(tester, '11-draft-jurnal-pengadaan');
    await _openMenu(tester, 'Katalog Laporan');
    await _shot(tester, '12-katalog-laporan-pengadaan');
  });
}

Future<void> _openMenu(WidgetTester tester, String label) async {
  await _tapSidebar(tester, label);
  await _wait(tester, () => find.text(label).evaluate().isNotEmpty,
      reason: 'Menu $label tidak terbuka', seconds: 60);
  await _waitNoSpinner(tester, seconds: 90);
  await _tutupOnboardingJikaAda(tester);
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((e) => e.data)
      .whereType<String>()
      .where((e) => e.trim().isNotEmpty)
      .take(120)
      .join(' | ');
  // ignore: avoid_print
  print('UAT_PENGADAAN=$label TEXT=$text');
}

Future<void> _tutupOnboardingJikaAda(WidgetTester tester) async {
  // Dialog dijadwalkan sesudah konfigurasi/server selesai dimuat, sehingga
  // belum tentu sudah ada saat frame pertama halaman utama terbentuk.
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    final nanti = find.text('Nanti');
    if (nanti.evaluate().isNotEmpty) {
      await tester.tap(nanti.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 750));
      return;
    }
  }
}

Future<void> _tapSidebar(WidgetTester tester, String label) async {
  final list = find.byType(ListView).first;
  var target = find.descendant(of: list, matching: find.text(label));
  for (var i = 0; i < 10 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 150));
    target = find.descendant(of: list, matching: find.text(label));
  }
  for (var i = 0; i < 10 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, 500));
    await tester.pump(const Duration(milliseconds: 150));
    target = find.descendant(of: list, matching: find.text(label));
  }
  expect(target, findsOneWidget, reason: 'Sidebar $label tidak ditemukan');
  final ink = find.ancestor(of: target, matching: find.byType(InkWell)).first;
  tester.widget<InkWell>(ink).onTap?.call();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _waitNoSpinner(WidgetTester tester, {int seconds = 60}) async {
  await _wait(
      tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'Layar masih memuat', seconds: seconds);
}

Future<void> _wait(WidgetTester tester, bool Function() condition,
    {required String reason, int seconds = 45}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) return;
  }
  throw StateError(reason);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 500));
  // Test-only capture: RenderView.layer tidak mempunyai API publik ekuivalen
  // yang dapat menyimpan seluruh jendela Windows tanpa driver eksternal.
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak tersedia');
  final image =
      // ignore: deprecated_member_use
      await layer.toImage(tester.binding.renderView.paintBounds, pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $name gagal');
  final directory = Directory(_outputDir);
  directory.createSync(recursive: true);
  File('${directory.path}\\$name.png')
      .writeAsBytesSync(data.buffer.asUint8List());
}
