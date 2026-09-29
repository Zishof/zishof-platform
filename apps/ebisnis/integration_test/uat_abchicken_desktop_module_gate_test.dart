import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/draft_jurnal_screen.dart';
import 'package:ebisnis/screens/ga_inventaris_screen.dart';
import 'package:ebisnis/screens/hrd_dasar_screen.dart';
import 'package:ebisnis/screens/inventory_sales/harga_screen.dart';
import 'package:ebisnis/screens/inventory_sales/hutang_supplier_screen.dart';
import 'package:ebisnis/screens/inventory_sales/laporan_opname_screen.dart';
import 'package:ebisnis/screens/inventory_sales/master_supplier_screen.dart';
import 'package:ebisnis/screens/jurnal_umum_screen.dart';
import 'package:ebisnis/screens/kulakan_screen.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:ebisnis/screens/pengajuan_anda_screen.dart';
import 'package:ebisnis/screens/pengiriman_screen.dart';
import 'package:ebisnis/screens/produksi_screen.dart';
import 'package:ebisnis/screens/produk_screen.dart';
import 'package:ebisnis/screens/retur_penjualan_screen.dart';
import 'package:ebisnis/screens/riwayat_penjualan_analisis_screen.dart';
import 'package:ebisnis/screens/self_order_screen.dart';
import 'package:ebisnis/screens/setup_laporan_screen.dart';
import 'package:ebisnis/screens/shift_otomatis_screen.dart';
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
      await _potret(tester, '34-hrd-${_slug(tab)}');
    }
    await _potret(tester, '34-sdm-hrd-semua-tab-lulus');

    await _buka(tester, '35', 'Inventaris General Affair',
        const GaInventarisScreen(), hasil);
    final pengajuanGa = find.text('Pengajuan');
    if (pengajuanGa.evaluate().isNotEmpty) {
      await tester.tap(pengajuanGa.last, warnIfMissed: false);
      await _tungguSelesai(tester, 'Pengajuan Inventaris Outlet');
      await _potret(tester, '35-ga-pengajuan');
      final ajukan = find.text('Ajukan');
      if (ajukan.evaluate().isNotEmpty) {
        await tester.tap(ajukan.last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        await _potret(tester, '35-ga-form-permintaan');
        final jenis = find.byType(DropdownButtonFormField<String>);
        if (jenis.evaluate().isNotEmpty) {
          await tester.tap(jenis.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
          final retur = find.text('Retur inventaris');
          if (retur.evaluate().isNotEmpty) {
            await tester.tap(retur.last, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));
            await _potret(tester, '35-ga-form-retur');
          }
          await tester.tap(jenis.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
          final pindah = find.text('Perpindahan inventaris');
          if (pindah.evaluate().isNotEmpty) {
            await tester.tap(pindah.last, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 300));
            await _potret(tester, '35-ga-form-perpindahan');
          }
        }
        final batal = find.text('Batal');
        if (batal.evaluate().isNotEmpty) {
          await tester.tap(batal.last, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
      if (find.text('Pengajuan Inventaris Outlet').evaluate().isNotEmpty) {
        Navigator.of(tester.element(find.text('Pengajuan Inventaris Outlet')))
            .pop();
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await _buka(tester, '36', 'Self Order QR', const SelfOrderScreen(), hasil);
    await _buka(tester, '37', 'Otomasi Shift Kasir',
        const ShiftOtomatisScreen(), hasil);
    await _buka(tester, '38', 'Master Produk', const ProdukScreen(), hasil);
    final aksiMassal = find.byTooltip('Aksi Massal').evaluate().isNotEmpty
        ? find.byTooltip('Aksi Massal')
        : find.textContaining('Aksi Massal');
    if (aksiMassal.evaluate().isNotEmpty) {
      await tester.tap(aksiMassal.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      await _potret(tester, '38-produk-aksi-massal');
      final hapusResep = find.text('Hapus resep dan ingredient terpilih');
      if (hapusResep.evaluate().isNotEmpty) {
        await tester.tap(hapusResep.last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));
        await _potret(tester, '38-produk-hapus-resep-ingredient');
      }
      final hapusCustom = find.text('Hapus pilihan custom menu/ekstra');
      if (hapusCustom.evaluate().isNotEmpty) {
        await tester.tap(hapusCustom.last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));
        await _potret(tester, '38-produk-hapus-custom-menu');
      }
      final batal = find.text('Batal');
      if (batal.evaluate().isNotEmpty) {
        await tester.tap(batal.last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    await _buka(tester, '39', 'Master Harga', const HargaScreen(), hasil);
    final hargaKanal = find.text('Harga per Kanal');
    if (hargaKanal.evaluate().isNotEmpty) {
      await tester.tap(hargaKanal.last, warnIfMissed: false);
      await _tungguSelesai(tester, 'Harga per Kanal');
      await _potret(tester, '39-harga-per-kanal');
    }
    await _buka(tester, '40', 'Analisis Penjualan',
        const RiwayatPenjualanAnalisisScreen(), hasil);
    await _buka(tester, '41', 'Laporan Transaksi',
        const LaporanTransaksiScreen(), hasil);
    for (final tab in const [
      'Report Order',
      'Report Sesi',
      'Transaksi Per Kasir',
      'Report Payment',
      'Penjualan per Kasir',
      'Penerimaan per Kasir',
      'Rincian Produk',
    ]) {
      final tombol = find.text(tab);
      if (tombol.evaluate().isEmpty) continue;
      await tester.tap(tombol.last, warnIfMissed: false);
      await _tungguSelesai(tester, 'Laporan Transaksi $tab');
      await _potret(tester, '41-laporan-${_slug(tab)}');
    }
    await _buka(tester, '42', 'Waste Produksi',
        const ProduksiScreen(bagian: BagianProduksi.productionWaste), hasil);
    await _buka(tester, '43', 'Kulakan', const KulakanScreen(), hasil);
    final returPembelian = find.text('Retur Pembelian');
    if (returPembelian.evaluate().isNotEmpty) {
      await tester.tap(returPembelian.last, warnIfMissed: false);
      await _tungguSelesai(tester, 'Retur Pembelian');
      await _potret(tester, '43-retur-pembelian');
    }
    await _buka(
        tester, '44', 'Hutang Supplier', const HutangSupplierScreen(), hasil);
    for (final tab in const ['Aging', 'Laporan Pembelian']) {
      final tombol = find.text(tab);
      if (tombol.evaluate().isEmpty) continue;
      await tester.tap(tombol.last, warnIfMissed: false);
      await _tungguSelesai(tester, 'Hutang Supplier $tab');
      await _potret(tester, '44-hutang-${_slug(tab)}');
    }
    await _buka(
        tester, '45', 'Master Supplier', const MasterSupplierScreen(), hasil);
    await _buka(
        tester, '46', 'Retur Penjualan', const ReturPenjualanScreen(), hasil);
    await _buka(tester, '47', 'Pengiriman',
        const PengirimanScreen(bagian: BagianPengiriman.deliveryOrder), hasil);
    await _buka(
        tester, '48', 'Rekonsiliasi Stok', const LaporanOpnameScreen(), hasil);

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
