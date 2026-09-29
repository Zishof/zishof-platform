import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/draft_jurnal_screen.dart';
import 'package:ebisnis/screens/ga_inventaris_screen.dart';
import 'package:ebisnis/screens/hrd_dasar_screen.dart';
import 'package:ebisnis/screens/jurnal_umum_screen.dart';
import 'package:ebisnis/screens/pengajuan_anda_screen.dart';
import 'package:ebisnis/screens/setup_laporan_screen.dart';
import 'package:ebisnis/services/pengikatan_tenant.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('menu penting ABChicken memakai layanan server yang tersedia',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const contextPath = String.fromEnvironment('POS_TEST_CONTEXT');
    const https = bool.fromEnvironment('POS_TEST_HTTPS', defaultValue: true);
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(host, isNotEmpty);
    expect(_outputDir, isNotEmpty);

    await initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';

    await tester.binding.setSurfaceSize(const Size(1920, 1032));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CoreDb.configureStorage('abchicken_uat_module_gate');
    await CoreDb.instance.db;
    addTearDown(() => CoreDb.instance.tutup());

    await ServerConfig.instance
        .simpan(host: host, contextPath: contextPath, https: https);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-AB-Chicken-Modul-Desktop',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    final ikat = await PengikatanTenant.periksaSetelahLogin();
    expect(ikat.bolehLanjut, isTrue,
        reason: 'Tenant akun UAT tidak dapat diikat ke perangkat.');
    expect(ikat.tenantAktifId, isNotNull,
        reason: 'Akun UAT wajib mempunyai tenant aktif.');
    await ApiClient.instance.simpanTenantId(ikat.tenantAktifId,
        tenantKode: ikat.tenantKode, tenantNama: ikat.tenantNama);
    final konfig = await ApiClient.instance.aksi('konfigurasi');
    Sesi.instance.terapkanKonfig(konfig);
    await ApiClient.instance.simpanUserIdAktif(Sesi.instance.userId);

    final hasil = StringBuffer('urutan,menu,hasil,berkas\n');
    await _buka(
        tester, '30', 'Pengajuan Anda', const PengajuanAndaScreen(), hasil);
    await _buka(tester, '31', 'Draft Jurnal', const DraftJurnalScreen(), hasil);
    await _buka(tester, '32', 'Jurnal Umum', const JurnalUmumScreen(), hasil);
    await _buka(
        tester, '33', 'Setup Laporan', const SetupLaporanScreen(), hasil);

    // Simulasikan instalasi lama: token dan tenant sudah ada, tetapi userId
    // belum pernah disimpan. Layar HRD wajib memulihkannya dari konfigurasi.
    Sesi.instance.userId = '';
    await _buka(tester, '34', 'SDM HRD', const HrdDasarScreen(), hasil);

    for (final tab in const [
      'Cuti & Izin',
      'Kehadiran',
      'Kedisiplinan',
      'Payroll',
      'Karier & Gaji',
      'Kinerja',
      'Riwayat',
      'Master HRD',
    ]) {
      final tombol = find.text(tab);
      expect(tombol, findsWidgets, reason: 'Tab HRD $tab tidak tersedia.');
      await tester.tap(tombol.last, warnIfMissed: false);
      await _tungguSelesai(tester, 'Tab HRD $tab');
      await _pastikanTanpaAksiTidakDikenal(tester, 'Tab HRD $tab');
    }
    await _potret(tester, '34-sdm-hrd-semua-tab-lulus');

    await _buka(tester, '35', 'Inventaris General Affair',
        const GaInventarisScreen(), hasil);

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);
    await File('${dir.path}\\hasil-gate-modul-desktop.csv')
        .writeAsString(hasil.toString(), flush: true);
  });
}

Future<void> _buka(WidgetTester tester, String urutan, String menu,
    Widget layar, StringBuffer hasil) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: layar is SetupLaporanScreen ? Scaffold(body: layar) : layar,
  ));
  await _tungguSelesai(tester, menu);
  await _pastikanTanpaAksiTidakDikenal(tester, menu);
  final nama = '$urutan-${_slug(menu)}';
  final berkas = await _potret(tester, nama);
  hasil.writeln('$urutan,"$menu",LULUS,"$berkas"');
}

Future<void> _tungguSelesai(WidgetTester tester, String menu) async {
  final batas = DateTime.now().add(const Duration(seconds: 90));
  var pernahMemuat = false;
  while (DateTime.now().isBefore(batas)) {
    await tester.pump(const Duration(milliseconds: 300));
    final sedangMemuat =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    pernahMemuat = pernahMemuat || sedangMemuat;
    if (!sedangMemuat) {
      await tester.pump(const Duration(milliseconds: 700));
      return;
    }
  }
  fail('$menu tidak selesai memuat (spinner=$pernahMemuat).');
}

Future<void> _pastikanTanpaAksiTidakDikenal(
    WidgetTester tester, String menu) async {
  final teks = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? '')
      .where((nilai) => nilai.trim().isNotEmpty)
      .toList();
  final galat = teks.where((nilai) {
    final kecil = nilai.toLowerCase();
    return kecil.contains('aksi tidak dikenal') ||
        kecil.contains('bad state: konteks tenant') ||
        kecil.contains('belum dapat dimuat');
  }).toList();
  expect(galat, isEmpty,
      reason: '$menu menampilkan kegagalan layanan: ${galat.join(' | ')}');
}

String _slug(String nilai) => nilai
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

Future<String> _potret(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 400));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) {
    throw StateError('Render layer $nama tidak tersedia.');
  }
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal dibuat.');
  final dir = Directory(_outputDir);
  await dir.create(recursive: true);
  final file = File('${dir.path}\\$nama.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  expect(file.lengthSync(), greaterThan(10000));
  return file.path;
}
