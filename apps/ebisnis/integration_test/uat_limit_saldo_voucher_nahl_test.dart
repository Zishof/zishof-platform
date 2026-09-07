import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/anggota/tab_pengajuan_limit.dart';
import 'package:ebisnis/screens/anggota/tab_saldo_voucher.dart';
import 'package:ebisnis/screens/hak_akses_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue:
      r'C:\opt\Claude-Workspace\artifacts\uat-limit-saldo-voucher-20260908',
);
const _preferencesFile = String.fromEnvironment('POS_TEST_PREFERENCES_FILE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'UAT live Nahl: verifikator limit dan saldo voucher selalu terbaru',
      (tester) async {
    expect(_preferencesFile, isNotEmpty,
        reason: 'POS_TEST_PREFERENCES_FILE wajib diisi.');
    final preferences = jsonDecode(File(_preferencesFile).readAsStringSync())
        as Map<String, dynamic>;
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

    final konfigurasi = await ApiClient.instance.aksi('konfigurasi', const {});
    expect(konfigurasi['bolehVerifikasiLimitMember'], isTrue,
        reason: 'Role aktif belum mendapat hak verifikasi limit.');
    Sesi.instance.terapkanKonfig(konfigurasi);

    await _pumpPanel(tester, const AnggotaTabPengajuanLimit());
    await _tunggu(
      tester,
      () => find.text('MENUNGGU').evaluate().isNotEmpty,
      alasan: 'Daftar pengajuan limit tidak selesai dimuat.',
    );
    expect(
      find.textContaining('Role Anda belum diizinkan'),
      findsNothing,
      reason: 'Role verifikator masih ditolak pada UI.',
    );
    expect(find.textContaining('Fathia Lulu Shakila'), findsWidgets);
    expect(find.byTooltip('Setujui'), findsWidgets);
    expect(find.byTooltip('Tolak'), findsWidgets);
    await _potret(tester, '01-pengajuan-limit-verifikator-aktif');

    // Uji saldo dilakukan sebelum AppShell Hak Akses agar lifecycle layanan
    // global pada shell tidak ikut memengaruhi panel finansial yang sedang
    // diisolasi.
    await _pumpPanel(tester, const AnggotaTabSaldoVoucher());
    await _tunggu(
      tester,
      () => find.textContaining('Data server diperbarui').evaluate().isNotEmpty,
      alasan: 'Saldo Voucher tidak mendapat data server terbaru.',
    );
    expect(find.textContaining('Data offline'), findsNothing,
        reason: 'UAT online justru memakai cache offline.');
    final pencarian = find.byType(TextField);
    expect(pencarian, findsOneWidget);
    await tester.enterText(pencarian, 'Fathia Lulu Shakila');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Fathia Lulu Shakila'), findsWidgets);
    expect(find.text('Rp 947.409'), findsWidgets,
        reason: 'Saldo akhir Fathia tidak sama dengan mutasi server terbaru.');
    await _potret(tester, '03-saldo-voucher-data-server-terbaru');

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HakAksesScreen(),
    ));
    await _tunggu(
      tester,
      () => find.text('Admin').evaluate().isNotEmpty,
      alasan: 'Daftar Hak Akses tidak selesai dimuat.',
    );
    await _tutupDialogSinkronisasiAwal(tester);
    await tester.tap(find.text('Admin').last);
    await _tunggu(
      tester,
      () => find
          .text('Boleh memverifikasi transaksi melebihi limit')
          .evaluate()
          .isNotEmpty,
      alasan: 'Sakelar hak verifikasi limit tidak tampil.',
    );
    final switchFinder = find.descendant(
      of: find.ancestor(
        of: find.text('Boleh memverifikasi transaksi melebihi limit'),
        matching: find.byType(SwitchListTile),
      ),
      matching: find.byType(Switch),
    );
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isTrue,
        reason: 'Sakelar role Admin tidak memuat nilai server yang aktif.');
    await _potret(tester, '02-hak-akses-verifikasi-limit-aktif');
  });
}

Future<void> _pumpPanel(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(body: SafeArea(child: panel)),
  ));
  await tester.pump(const Duration(milliseconds: 100));
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
    if (find.text('Admin').hitTestable().evaluate().isNotEmpty) return;
  }
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
