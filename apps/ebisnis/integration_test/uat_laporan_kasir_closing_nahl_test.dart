import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue:
      r'C:\opt\CodeBaseDesktopDanMobile\tmp\uat-laporan-kasir-closing-nahl',
);
const _preferencesFile = String.fromEnvironment('POS_TEST_PREFERENCES_FILE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT live Nahl: kas belum closing tidak menjadi minus semu',
      (tester) async {
    expect(_preferencesFile, isNotEmpty,
        reason: 'POS_TEST_PREFERENCES_FILE wajib diisi.');
    final preferences = jsonDecode(
      File(_preferencesFile).readAsStringSync(),
    ) as Map<String, dynamic>;
    final token = '${preferences['flutter.token'] ?? ''}'.trim();
    expect(token, isNotEmpty, reason: 'Token sesi Nahl tidak tersedia.');

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await ServerConfig.instance.simpan(
      host: 'an-nahl.santri.info',
      contextPath: 'nahl',
      https: true,
    );
    await ApiClient.instance.simpanToken(token);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const LaporanTransaksiScreen(),
    ));
    await _tunggu(
        tester, () => find.text('Transaksi Per Kasir').evaluate().isNotEmpty,
        alasan: 'Tab Transaksi Per Kasir tidak tersedia.');
    final mainTabBar = find.byWidgetPredicate(
      (widget) =>
          widget is TabBar &&
          widget.tabs.any(
            (tab) => tab is Tab && tab.text == 'Transaksi Per Kasir',
          ),
      description: 'TabBar utama Laporan Transaksi',
    );
    expect(mainTabBar, findsOneWidget);
    final tabBar = tester.widget<TabBar>(mainTabBar);
    tabBar.controller!.animateTo(2);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _tutupDialogSinkronisasiAwal(tester);
    await _tunggu(
        tester, () => find.text('Terapkan').hitTestable().evaluate().isNotEmpty,
        alasan: 'Filter Transaksi Per Kasir tidak terbuka.');

    await _pilihTanggalEnamSeptember(tester);
    await tester.tap(find.text('Terapkan').hitTestable().first);
    await _tunggu(
      tester,
      () =>
          find.text('47 transaksi').evaluate().isNotEmpty &&
          find.text('Chusnul Mutia').evaluate().isNotEmpty &&
          find.text('Belum closing').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
      alasan: 'Data live 6 September 2026 tidak selesai dimuat.',
    );

    expect(find.text('-Rp 471.500'), findsNothing,
        reason: 'Minus semu lama masih tampil.');
    expect(find.text('-Rp471.500'), findsNothing,
        reason: 'Minus semu lama masih tampil.');
    expect(find.text('Belum ada closing'), findsOneWidget);
    expect(
        find.textContaining('1 kasir belum memiliki closing'), findsOneWidget);
    await _potret(tester, '01-ringkasan-belum-closing');

    if (find.text('Belum dicatat').evaluate().isEmpty) {
      await tester.tap(find.text('Chusnul Mutia').hitTestable().first);
    }
    await _tunggu(
      tester,
      () =>
          find.text('Belum dicatat').evaluate().isNotEmpty &&
          find.text('Belum dapat dihitung').evaluate().isNotEmpty,
      alasan: 'Rincian kasir belum menampilkan status closing yang benar.',
    );
    await _potret(tester, '02-rincian-kasir-belum-closing');

    await tester.tap(find.text('Belum closing').hitTestable().first);
    await _tunggu(
      tester,
      () =>
          find.text('Rekonsiliasi Chusnul Mutia').evaluate().isNotEmpty &&
          find
              .textContaining('Selisih bukan angka penjualan')
              .evaluate()
              .isNotEmpty,
      alasan: 'Popup penjelasan belum closing tidak tampil.',
    );
    await _potret(tester, '03-popup-penjelasan-belum-closing');
  });
}

Future<void> _tutupDialogSinkronisasiAwal(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    final nanti = find.text('Nanti').hitTestable();
    if (nanti.evaluate().isNotEmpty) {
      await tester.tap(nanti.first);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      return;
    }
    if (find.text('Terapkan').hitTestable().evaluate().isNotEmpty) return;
  }
}

Future<void> _pilihTanggalEnamSeptember(WidgetTester tester) async {
  var tanggalHariIni = find.text('2026-09-07').hitTestable();
  expect(tanggalHariIni, findsNWidgets(2));
  await tester.tap(tanggalHariIni.first);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text('6').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));

  tanggalHariIni = find.text('2026-09-07').hitTestable();
  expect(tanggalHariIni, findsOneWidget);
  await tester.tap(tanggalHariIni.first);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(find.text('6').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _tunggu(
  WidgetTester tester,
  bool Function() selesai, {
  required String alasan,
}) async {
  for (var i = 0; i < 180; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (selesai()) return;
  }
  fail(alasan);
}

Future<void> _potret(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer $nama tidak ada.');
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal.');
  final directory = Directory(_outputDir);
  await directory.create(recursive: true);
  final file = File('${directory.path}\\$nama.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  if (file.lengthSync() < 5000) {
    throw StateError('Screenshot $nama hanya ${file.lengthSync()} byte.');
  }
}
