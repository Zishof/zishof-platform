import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/main.dart' as app;
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/screens/login_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR',
    defaultValue:
        r'C:\opt\AIS\ais\src\main\docs\pos\manual-keuangan-akuntansi\screenshots-uat');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT seluruh submenu Keuangan dan integrasi Akuntansi',
      (tester) async {
    final oldError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = oldError);
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    Map<String, dynamic>? login;
    Object? loginError;
    for (var attempt = 1; attempt <= 4 && login == null; attempt++) {
      try {
        login = await ApiClient.instance.aksi('login', {
          'username': username,
          'password': password,
          'labelPerangkat': 'UAT-Manual-Keuangan',
        });
      } catch (e) {
        loginError = e;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    if (login == null) throw StateError('Login UAT gagal: $loginError');
    await ApiClient.instance.simpanToken(login['token'] as String);
    app.main();
    await _waitUntil(
      tester,
      () =>
          find.byType(KasirScreen).evaluate().isNotEmpty ||
          find.byType(LoginScreen).evaluate().isNotEmpty,
      reason: 'Layar awal tidak selesai dimuat',
      seconds: 180,
    );
    if (find.byType(LoginScreen).evaluate().isNotEmpty) {
      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), username);
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), password);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Masuk'));
    }
    await _waitUntil(
      tester,
      () => find.byType(KasirScreen).evaluate().isNotEmpty,
      reason: 'Sesi POS belum siap',
      seconds: 180,
    );
    FlutterError.onError = (detail) {
      if (detail.exceptionAsString().contains('A RenderFlex overflowed')) {
        // Layout defects remain visible in screenshots without stopping the
        // remaining functional UAT.
        // ignore: avoid_print
        print('UAT_LAYOUT_OVERFLOW=${detail.exceptionAsString()}');
        return;
      }
      oldError?.call(detail);
    };

    const accountingOnly =
        bool.fromEnvironment('POS_TEST_FINANCE_ACCOUNTING_ONLY');
    const tailOnly = bool.fromEnvironment('POS_TEST_FINANCE_TAIL_ONLY');
    await _shot(tester, '00-layar-awal-ebisnis');
    if (!accountingOnly) {
      await _tapSidebar(tester, 'KEUANGAN');
      await _shot(tester, '01-menu-keuangan-terbuka');
    }

    if (!tailOnly && !accountingOnly) {
      const menus = <(String, String, String?)>[
        ('Uang Muka (Cash Advance)', '02-uang-muka-daftar', 'Pengajuan Baru'),
        ('Pertanggungjawaban Uang Muka', '04-pj-uang-muka-daftar', 'LPJ Baru'),
        ('Kas Besar', '06-kas-besar-daftar', 'Pengeluaran Baru'),
        ('Pertanggungjawaban Kas Besar', '08-pj-kas-besar-daftar', 'PJ Baru'),
        ('Kas Kecil', '10-kas-kecil-daftar', 'Pengeluaran Baru'),
        (
          'Penggantian Kas Kecil (Reimbursement)',
          '12-penggantian-kas-kecil-daftar',
          'Penggantian Baru'
        ),
        ('Dana Talangan', '14-dana-talangan-daftar', 'Talangan Baru'),
        (
          'Reimbursement Pegawai',
          '16-reimbursement-pegawai-daftar',
          'Pengajuan Baru'
        ),
      ];
      for (var i = 0; i < menus.length; i++) {
        final item = menus[i];
        await _openMenu(tester, item.$1);
        await _shot(tester, item.$2);
        if (item.$3 != null && find.text(item.$3!).evaluate().isNotEmpty) {
          await tester.tap(find.text(item.$3!).last);
          await _waitUntil(
            tester,
            () => find.text('Batal').evaluate().isNotEmpty,
            reason: 'Form ${item.$1} tidak terbuka',
            seconds: 30,
          );
          final formNumber = (i * 2) + 3;
          await _shot(tester,
              '${formNumber.toString().padLeft(2, '0')}-${item.$2.substring(3).replaceAll('-daftar', '-formulir')}');
          await tester.tap(find.text('Batal').last);
          await tester.pump(const Duration(milliseconds: 700));
        }
      }

      await _openMenu(tester, 'Master Data Keuangan');
      await _shot(tester, '18-master-jenis-uang-muka');
      await _tapTab(tester, 'Jenis Pengeluaran');
      await _waitNoSpinner(tester, seconds: 90);
      await _shot(tester, '19-master-jenis-pengeluaran-terpetakan');
      await _tapTab(tester, 'Kategori Biaya Sales');
      await _waitNoSpinner(tester, seconds: 90);
      await _shot(tester, '20-master-kategori-biaya-sales-terpetakan');

      await _openMenu(tester, 'Proses Transfer');
      await _shot(tester, '21-proses-transfer-dasbor');
      await _tapTab(tester, 'Proses Transfer');
      await _waitNoSpinner(tester, seconds: 90);
      await _shot(tester, '22-proses-transfer-terealisasi');
      for (final tab in const [
        ('Pembayaran Vendor', '23-pembayaran-vendor'),
        ('Transitori Menunggu', '24-transitori-menunggu'),
        ('Proses Transitori', '25-proses-transitori'),
      ]) {
        if (find.text(tab.$1).evaluate().isNotEmpty) {
          await _tapTab(tester, tab.$1);
          await _waitNoSpinner(tester, seconds: 90);
          await _shot(tester, tab.$2);
        }
      }

      await _openMenu(tester, 'Penomoran Dokumen Keuangan');
      await _shot(tester, '26-penomoran-alur-dokumen');
      await _tapTab(tester, 'Templat Nomor');
      await _waitNoSpinner(tester, seconds: 60);
      await _shot(tester, '27-penomoran-templat-standar');
    }

    if (!accountingOnly) {
      await _openMenu(tester, 'Bayar Pajak');
      await _shot(tester, '28-bayar-pajak-dasbor');
      await _tapTab(tester, 'Pajak');
      await _waitNoSpinner(tester, seconds: 90);
      await _shot(tester, '29-pajak-terutang');
      await _tapTab(tester, 'Riwayat Setoran');
      await tester.pump(const Duration(seconds: 1));
      await _shot(tester, '30-pajak-riwayat-setoran');
    }

    await _tapSidebar(tester, 'AKUNTANSI');
    await _openMenu(tester, 'Draft Jurnal');
    await _waitNoSpinner(tester, seconds: 120);
    await _shot(tester, '31-integrasi-draft-jurnal-semua');
    if (find.text('Uang Muka dan Kas').evaluate().isNotEmpty) {
      await tester.tap(find.text('Uang Muka dan Kas').last);
      await tester.pump(const Duration(seconds: 1));
      await _shot(tester, '32-integrasi-jurnal-uang-muka-dan-kas');
    }
    if (find.text('Pengajuan Transfer').evaluate().isNotEmpty) {
      await _tapTab(tester, 'Pengajuan Transfer');
      await _shot(tester, '33-integrasi-jurnal-pengajuan-transfer');
    }

    await _openMenu(tester, 'Katalog Laporan');
    await _waitNoSpinner(tester, seconds: 90);
    await _runReport(
      tester,
      id: 'akn_laba_rugi',
      title: 'Laba Rugi (Berbasis Jurnal Akuntansi)',
      file: '34-laporan-laba-rugi-integrasi-keuangan',
    );
    await _runReport(
      tester,
      id: 'akn_arus_kas',
      title: 'Arus Kas (Berbasis Jurnal Akuntansi)',
      file: '35-laporan-arus-kas-integrasi-keuangan',
    );
    await _runReport(
      tester,
      id: 'akn_jurnal',
      title: 'Keseluruhan Jurnal (Jurnal Umum)',
      file: '36-laporan-keseluruhan-jurnal',
    );
  });
}

Future<void> _openMenu(WidgetTester tester, String label) async {
  await _tapSidebar(tester, label);
  await _waitUntil(
    tester,
    () => find.text(label).evaluate().isNotEmpty,
    reason: 'Menu $label tidak terbuka',
    seconds: 60,
  );
  await _waitNoSpinner(tester, seconds: 90);
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data)
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .take(80)
      .join(' | ');
  // ignore: avoid_print
  print('UAT_MENU=$label TEXT=$text');
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  final candidates = find.text(label);
  expect(candidates, findsWidgets, reason: 'Tab $label tidak ditemukan');
  final target = candidates.last;
  try {
    await Scrollable.ensureVisible(
      tester.element(target),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pump(const Duration(milliseconds: 250));
  } catch (_) {
    // Some fixed TabBars have no scrollable ancestor.
  }
  await tester.tap(target);
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _runReport(
  WidgetTester tester, {
  required String id,
  required String title,
  required String file,
}) async {
  final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Cari laporan...');
  await tester.enterText(search, title);
  await tester.pump(const Duration(seconds: 1));
  final reportText = find
      .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(title));
  expect(reportText, findsOneWidget);
  Navigator.of(tester.element(reportText)).push(MaterialPageRoute(
      builder: (_) => LaporanDetailScreen(item: {
            'id': id,
            'judul': title,
            'ket': 'Bukti integrasi transaksi Keuangan ke jurnal Akuntansi',
            'satker': false,
          })));
  await tester.pump(const Duration(seconds: 1));
  await _waitUntil(
    tester,
    () =>
        find.byType(LaporanDetailScreen).evaluate().isNotEmpty &&
        find.text('Tampilkan').evaluate().isNotEmpty,
    reason: 'Detail laporan $title tidak terbuka',
  );
  final endLabel = find.text('Tanggal Sampai');
  if (endLabel.evaluate().isNotEmpty) {
    final ink =
        find.ancestor(of: endLabel, matching: find.byType(InkWell)).first;
    await tester.tap(ink);
    await _waitUntil(
      tester,
      () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
      reason: 'Pemilih tanggal laporan tidak terbuka',
    );
    if (find.text('30').evaluate().isNotEmpty) {
      await tester.tap(find.text('30').last);
    }
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.tap(find.text('Tampilkan').last);
  expect(await _waitNoSpinner(tester, seconds: 120), isTrue,
      reason: 'Laporan $title terus memuat');
  await tester.pump(const Duration(seconds: 1));
  await _shot(tester, file);
  await tester.tap(find.byType(BackButton));
  await _waitUntil(
    tester,
    () => find.byType(LaporanDetailScreen).evaluate().isEmpty,
    reason: 'Tidak dapat kembali dari laporan $title',
  );
}

Future<void> _tapSidebar(WidgetTester tester, String label) async {
  // scrollUntilVisible mengharuskan Finder menunjuk widget Scrollable, bukan
  // pembungkus ListView-nya. Flutter 3.27 menegakkan tipe ini secara ketat.
  final sidebar = find.byType(Scrollable).first;
  var target = find.descendant(of: sidebar, matching: find.text(label));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(label),
      500,
      scrollable: sidebar,
      maxScrolls: 30,
    );
    await tester.pump(const Duration(milliseconds: 250));
    target = find.descendant(of: sidebar, matching: find.text(label));
  }
  expect(target, findsOneWidget, reason: 'Sidebar $label tidak ditemukan');
  final ink = find.ancestor(of: target, matching: find.byType(InkWell)).first;
  final onTap = tester.widget<InkWell>(ink).onTap;
  expect(onTap, isNotNull, reason: 'Sidebar $label tidak aktif');
  onTap!.call();
  await tester.pump(const Duration(seconds: 1));
  if (label == 'KEUANGAN' || label == 'AKUNTANSI') {
    await Scrollable.ensureVisible(
      tester.element(target),
      alignment: 0.05,
      duration: Duration.zero,
    );
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<bool> _waitNoSpinner(WidgetTester tester, {int seconds = 60}) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return true;
  }
  return false;
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  int seconds = 120,
}) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (condition()) return;
  }
  fail(reason);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 500));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer $name tidak ada');
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $name gagal');
  final directory = Directory(_outputDir);
  await directory.create(recursive: true);
  await File('${directory.path}\\$name.png')
      .writeAsBytes(data.buffer.asUint8List(), flush: true);
}
