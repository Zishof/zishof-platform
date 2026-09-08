import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:ebisnis/product_profile.dart';
import 'package:ebisnis/screens/apotik/beranda_apotik_screen.dart';
import 'package:ebisnis/screens/apotik/kasir_apotik_screen.dart';
import 'package:ebisnis/screens/apotik/laporan_apotik_screen.dart';
import 'package:ebisnis/screens/apotik/menu_apotik_screen.dart';
import 'package:ebisnis/screens/apotik/pengadaan_apotik_screen.dart';
import 'package:ebisnis/screens/apotik/persediaan_apotik_screen.dart';
import 'package:ebisnis/screens/pengadaan_bast_screen.dart';
import 'package:ebisnis/screens/pengadaan_bayar_screen.dart';
import 'package:ebisnis/screens/pengadaan_po_screen.dart';
import 'package:ebisnis/screens/pengadaan_pr_screen.dart';
import 'package:ebisnis/screens/pengadaan_tagihan_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-simplified-manual',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'UAT live tampilan Apotik sederhana dan bukti user manual',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await initializeDateFormatting('id_ID');

      await _loginDanKonfigurasi();

      final ringkasan = <String, dynamic>{
        'waktuUat': DateTime.now().toIso8601String(),
        'server': 'https://${const String.fromEnvironment('POS_TEST_HOST')}/'
            '${const String.fromEnvironment('POS_TEST_CONTEXT')}',
        'jenisUat': 'LIVE_READONLY_DAN_CAPTURE_UI',
      };

      final itemResponse = await _aksi('apotik_item_cari', {
        'page': 1,
        'page_size': 100,
      });
      final items = _rows(itemResponse);
      expect(items.length, greaterThanOrEqualTo(100));
      ringkasan['produkObatTerbaca'] = items.length;
      ringkasan['produkObatTotal'] = itemResponse['total'];

      final referensi = await _aksi('apotik_item_referensi', const {});
      expect(_rowsDari(referensi, 'satuan'), isNotEmpty);
      expect(_rowsDari(referensi, 'jenis'), isNotEmpty);
      ringkasan['referensiSetupProduk'] = {
        'satuan': _rowsDari(referensi, 'satuan').length,
        'jenis': _rowsDari(referensi, 'jenis').length,
      };

      for (final entry in const {
        'formulaRacikan': 'apotik_racikan_list',
        'formulaProduksi': 'apotik_produksi_katalog',
        'resepMenunggu': 'apotik_resep_list',
        'batchMonitor': 'apotik_batch_monitor',
        'laporanPenjualan': 'apotik_laporan_penjualan',
      }.entries) {
        final parameter = <String, dynamic>{'page_size': 100};
        if (entry.key == 'resepMenunggu') parameter['hanya_menunggu'] = true;
        if (entry.key == 'batchMonitor') parameter['hari_ke_depan'] = 365;
        final response = await _aksi(entry.value, parameter);
        final jumlah = _rows(response).length;
        expect(jumlah, greaterThanOrEqualTo(100),
            reason: '${entry.value} harus menyediakan sedikitnya 100 data');
        ringkasan[entry.key] = jumlah;
      }

      for (final entry in const {
        'pengadaanPR': 'pengadaan_pr_daftar',
        'pengadaanPO': 'pengadaan_po_daftar',
        'pengadaanBAST': 'pengadaan_bast_daftar',
        'tagihanVendor': 'pengadaan_tagihan_daftar',
        'pembayaranVendor': 'pengadaan_bayar_daftar',
      }.entries) {
        final jumlah = (await _paginasiMinimal(
          entry.value,
          minimum: 100,
        ))
            .length;
        expect(jumlah, greaterThanOrEqualTo(100),
            reason: '${entry.value} harus menyediakan sedikitnya 100 data');
        ringkasan[entry.key] = jumlah;
      }

      await _capturePage(
          tester, const BerandaApotikScreen(), '00-dashboard-apotik');
      await _capturePage(tester, const PersediaanApotikScreen(tabAwal: 0),
          '01-setup-produk-obat-daftar');
      await _captureSetupDialog(tester);
      await _capturePage(tester, const PersediaanApotikScreen(tabAwal: 1),
          '03-batch-kedaluwarsa');
      await _capturePage(
          tester, const PersediaanApotikScreen(tabAwal: 2), '04-stok-opname');
      await _capturePage(
          tester, const PersediaanApotikScreen(tabAwal: 3), '05-retur-obat');

      await _capturePage(
          tester, const PengadaanApotikScreen(), '06-pengadaan-lima-tahap');
      await _capturePageDanTab(tester, const PengadaanPrScreen(),
          '07-pengadaan-pr', 'Permintaan', '07b-daftar-pengadaan-pr');
      await _capturePageDanTab(tester, const PengadaanPoScreen(),
          '08-pengadaan-po', 'Pesanan', '08b-daftar-pengadaan-po');
      await _capturePageDanTab(tester, const PengadaanBastScreen(),
          '09-pengadaan-bast', 'Penerimaan', '09b-daftar-pengadaan-bast');
      await _capturePageDanTab(tester, const PengadaanTagihanScreen(),
          '10-terima-tagihan-vendor', 'Tagihan', '10b-daftar-tagihan-vendor');
      await _capturePageDanTab(tester, const PengadaanBayarScreen(),
          '11-pembayaran-vendor', 'Pembayaran', '11b-daftar-pembayaran-vendor');

      await _capturePage(
          tester, const KasirApotikScreen(), '12-kasir-otc-dan-resep');
      await _capturePrescriptionDialog(tester, items.first);
      await _capturePage(
          tester, const RacikanApotikScreen(), '14-racikan-pasien');
      await _capturePage(
          tester, const ProduksiFarmasiApotikScreen(), '15-produksi-farmasi');
      await _captureTebusResep(tester);
      await _capturePage(
          tester, const LaporanApotikScreen(), '17-monitoring-penjualan');
      await _capturePaymentDialog(tester, items.first);

      ringkasan['status'] = 'PASS';
      final dir = Directory(_outputDir)..createSync(recursive: true);
      File('${dir.path}\\uat-simplified-summary.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(ringkasan),
        flush: true,
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _loginDanKonfigurasi() async {
  const host = String.fromEnvironment('POS_TEST_HOST');
  const context = String.fromEnvironment('POS_TEST_CONTEXT');
  const username = String.fromEnvironment('POS_TEST_USERNAME');
  const password = String.fromEnvironment('POS_TEST_PASSWORD');
  expect(host, isNotEmpty);
  expect(username, isNotEmpty);
  expect(password, isNotEmpty);

  AppProductProfile.aktif = const AppProductProfile.apotik();
  await ServerConfig.instance
      .simpan(host: host, contextPath: context, https: true);
  final login = await ApiClient.instance.aksi('login', {
    'username': username,
    'password': password,
    'labelPerangkat': 'UAT-Apotik-Simplified-Manual-20260908',
  });
  await ApiClient.instance.simpanToken('${login['token']}');
  final konfigurasi = await _aksi('konfigurasi', const {});
  Sesi.instance.terapkanKonfig(konfigurasi);
  Sesi.instance
    ..tokoFilter = 1
    ..tokoId = 1
    ..tokoNama = 'Demo';
}

Future<Map<String, dynamic>> _aksi(
    String aksi, Map<String, dynamic> parameter) async {
  Object? terakhir;
  for (var percobaan = 1; percobaan <= 4; percobaan++) {
    try {
      final response = Map<String, dynamic>.from(
          await ApiClient.instance.aksi(aksi, parameter));
      expect(response['status'], anyOf('success', '00'),
          reason: '$aksi ditolak: ${response['description'] ?? response}');
      return response;
    } catch (error) {
      terakhir = error;
      if (percobaan < 4) {
        await Future<void>.delayed(Duration(milliseconds: 500 * percobaan));
      }
    }
  }
  throw StateError('$aksi gagal setelah empat percobaan: $terakhir');
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> response) =>
    ((response['data'] as List?) ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();

List<Map<String, dynamic>> _rowsDari(
        Map<String, dynamic> response, String key) =>
    ((response[key] as List?) ?? const [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();

Future<List<Map<String, dynamic>>> _paginasiMinimal(
  String aksi, {
  required int minimum,
  Map<String, dynamic> parameter = const {},
}) async {
  final hasil = <Map<String, dynamic>>[];
  final idTerlihat = <String>{};
  for (var halaman = 1; halaman <= 50 && hasil.length < minimum; halaman++) {
    final response = await _aksi(aksi, {
      ...parameter,
      'page': halaman,
      'page_size': 100,
    });
    final rows = _rows(response);
    if (rows.isEmpty) break;
    var barisBaru = 0;
    for (final row in rows) {
      final id = '${row['id'] ?? row['kode'] ?? jsonEncode(row)}';
      if (idTerlihat.add(id)) {
        hasil.add(row);
        barisBaru++;
      }
    }
    if (barisBaru == 0) break;
  }
  return hasil;
}

ThemeData _theme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Arial',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF154F3B)),
      extensions: const [ApotikDesignTokens.light],
    );

Future<void> _capturePage(WidgetTester tester, Widget page, String name) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: KeyedSubtree(key: ValueKey(name), child: page),
  ));
  await _tutupOnboardingJikaAda(tester);
  await _settle(tester);
  await _shot(tester, name);
}

Future<void> _capturePageDanTab(
  WidgetTester tester,
  Widget page,
  String dashboardName,
  String tabLabel,
  String listName,
) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: KeyedSubtree(key: ValueKey(dashboardName), child: page),
  ));
  await _tutupOnboardingJikaAda(tester);
  await _settle(tester);
  await _shot(tester, dashboardName);
  final tab = find.text(tabLabel);
  expect(tab, findsWidgets);
  await tester.tap(tab.last);
  await _settle(tester);
  await _shot(tester, listName);
}

Future<void> _captureSetupDialog(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: const KeyedSubtree(
      key: ValueKey('02-setup-produk-obat-form'),
      child: PersediaanApotikScreen(tabAwal: 0),
    ),
  ));
  await _tutupOnboardingJikaAda(tester);
  await _settle(tester);
  final add = find.byKey(const Key('tambah-produk-obat'));
  expect(add, findsOneWidget);
  await tester.tap(add);
  await _settle(tester);
  expect(find.text('Tambah Produk Obat'), findsWidgets);
  expect(find.text('Lokasi penyimpanan'), findsOneWidget);
  await _shot(tester, '02-setup-produk-obat-form');
  await tester.scrollUntilVisible(
    find.text('Lokasi penyimpanan'),
    320,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await _shot(tester, '02b-setup-produk-obat-lokasi');
  await tester.tap(find.text('Batal').last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _capturePrescriptionDialog(
    WidgetTester tester, Map<String, dynamic> item) async {
  final controller = ApotikPosController()
    ..mode = ApotikModePos.resep
    ..tambah(ApotikBarisKeranjang(
      item: item,
      qty: 1,
      harga: ((item['hargaJual'] as num?) ?? 0).toDouble(),
    ));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: AppShell(
      menuAktif: MenuEBisnis.kasirApotik,
      judul: 'Kasir Apotik — Resep Dokter',
      subjudul: 'Pembuatan resep baru lengkap di kasir',
      scrollable: false,
      body: ApotikPosPage(
        controller: controller,
        modeTersedia: const [ApotikModePos.resep],
        modeTerkunci: true,
      ),
    ),
  ));
  await _tutupOnboardingJikaAda(tester);
  await _settle(tester);
  final create = find.byKey(const Key('buat-resep-baru'));
  expect(create, findsOneWidget);
  await tester.tap(create);
  await _settle(tester);
  expect(find.text('Buat Resep Baru di Kasir'), findsOneWidget);
  expect(find.text('Dokter dan asal resep'), findsOneWidget);
  expect(find.text('Informasi klinis'), findsOneWidget);
  await _shot(tester, '13-form-resep-baru-lengkap');
  await tester.scrollUntilVisible(
    find.text('Informasi klinis'),
    320,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await _shot(tester, '13b-form-resep-informasi-klinis');
  await tester.tap(find.text('Batal').last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _capturePaymentDialog(
    WidgetTester tester, Map<String, dynamic> item) async {
  final controller = ApotikPosController()
    ..mode = ApotikModePos.otc
    ..tambah(ApotikBarisKeranjang(
      item: item,
      qty: 1,
      harga: ((item['hargaJual'] as num?) ?? 0).toDouble(),
    ));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: AppShell(
      menuAktif: MenuEBisnis.kasirApotik,
      judul: 'Kasir Apotik',
      subjudul: 'Pembayaran OTC / Obat Bebas',
      scrollable: false,
      body: ApotikPosPage(
        controller: controller,
        modeTersedia: const [ApotikModePos.otc, ApotikModePos.resep],
      ),
    ),
  ));
  await _tutupOnboardingJikaAda(tester);
  await _settle(tester);
  final pay = find.text('Bayar');
  expect(pay, findsWidgets);
  await tester.tap(pay.last);
  await _settle(tester);
  expect(find.text('Pembayaran'), findsWidgets);
  await _shot(tester, '12b-dialog-pembayaran-otc');
}

Future<void> _captureTebusResep(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: const KeyedSubtree(
      key: ValueKey('16-tebus-resep-dokter'),
      child: TebusResepApotikScreen(),
    ),
  ));
  await _tutupOnboardingJikaAda(tester);
  await _settle(tester);
  await _shot(tester, '16-tebus-resep-dokter');
  final nomorResep = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        RegExp(r'^RSP-').hasMatch(widget.data!),
    description: 'nomor resep berawalan RSP-',
  );
  expect(nomorResep, findsWidgets);
  await tester.tap(nomorResep.first);
  await _settle(tester);
  expect(find.text('Pasien / RM'), findsOneWidget);
  expect(find.text('Dokter/peresep'), findsOneWidget);
  expect(find.text('Diagnosis/indikasi'), findsOneWidget);
  await _shot(tester, '16b-detail-tebus-resep-dokter');
}

Future<void> _tutupOnboardingJikaAda(WidgetTester tester) async {
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

Future<void> _settle(WidgetTester tester) async {
  int? previous;
  var stable = 0;
  for (var i = 0; i < 360; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    final indicators = find.byType(CircularProgressIndicator).evaluate().length;
    if (indicators == 0 && i >= 4) {
      await tester.pump(const Duration(milliseconds: 750));
      return;
    }
    if (i >= 24 && indicators == previous) {
      stable++;
      if (stable >= 12) {
        await tester.pump(const Duration(seconds: 1));
        return;
      }
    } else {
      stable = 0;
    }
    previous = indicators;
  }
  throw StateError('Layar belum stabil setelah 90 detik');
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 500));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak tersedia');
  final image =
      // ignore: deprecated_member_use
      await layer.toImage(tester.binding.renderView.paintBounds, pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $name gagal');
  final directory = Directory(_outputDir)..createSync(recursive: true);
  File('${directory.path}\\$name.png')
      .writeAsBytesSync(data.buffer.asUint8List(), flush: true);
}
