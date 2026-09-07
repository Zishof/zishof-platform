import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:ebisnis/product_profile.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-live-readonly',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    AppProductProfile.aktif = const AppProductProfile.apotik();
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    if (host.isNotEmpty) {
      await ServerConfig.instance
          .simpan(host: host, contextPath: context, https: true);
    }
    await ServerConfig.instance.muat();
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    if (username.isNotEmpty && password.isNotEmpty) {
      final login = await ApiClient.instance.aksi('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-Apotik-Read-Only-20260908',
      });
      await ApiClient.instance.simpanToken('${login['token']}');
    } else {
      await ApiClient.instance.muatTokenTersimpan();
    }
    if (!ApiClient.instance.sudahLogin) {
      throw StateError(
        'Sesi login Apotik tidak ditemukan pada perangkat. Buka aplikasi dan '
        'login terlebih dahulu, lalu ulangi UAT read-only.',
      );
    }
    final konfigurasi = await ApiClient.instance.aksi('konfigurasi');
    Sesi.instance.terapkanKonfig(konfigurasi);
  });

  testWidgets('UAT live lima jalur kasir minimal 100 data', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hasil = <String, int>{};
    hasil['otc'] = await _pastikanSeratus(
      'apotik_item_cari',
      const {'page_size': 100},
    );
    hasil['resepDokter'] = await _pastikanSeratusResepLengkap(
      hanyaMenunggu: false,
    );
    hasil['racikan'] = await _pastikanSeratus(
      'apotik_racikan_list',
      const {'page_size': 100},
    );
    hasil['produksiFarmasi'] = await _pastikanSeratus(
      'apotik_produksi_katalog',
      const {'page_size': 100},
    );
    hasil['tebusResep'] = await _pastikanSeratusResepLengkap(
      hanyaMenunggu: true,
    );

    await _tampilkanMode(
      tester,
      ApotikModePos.otc,
      const Size(1440, 900),
      '01-live-otc-desktop',
    );
    await _tampilkanMode(
      tester,
      ApotikModePos.resep,
      const Size(1440, 900),
      '02-live-resep-dokter',
    );
    await _tampilkanMode(
      tester,
      ApotikModePos.racikan,
      const Size(1440, 900),
      '03-live-racikan',
    );
    await _tampilkanMode(
      tester,
      ApotikModePos.produksi,
      const Size(1440, 900),
      '04-live-produksi-farmasi',
    );
    await _tampilkanTebusResep(tester);
    await _tampilkanMode(
      tester,
      ApotikModePos.otc,
      const Size(390, 844),
      '06-live-mobile-tebus-resep-terlihat',
    );
    expect(find.text('Tebus Resep'), findsOneWidget);

    final ringkasan = File('$_outputDir\\uat-live-readonly-summary.txt');
    ringkasan.parent.createSync(recursive: true);
    ringkasan.writeAsStringSync(
      [
        'status=PASS',
        'waktu=${DateTime.now().toIso8601String()}',
        for (final entry in hasil.entries) '${entry.key}=${entry.value}',
        'provisioningSampleDilakukan=false',
        'mutasiTransaksi=false',
      ].join('\n'),
      flush: true,
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<int> _pastikanSeratus(
    String aksi, Map<String, dynamic> parameter) async {
  final respons = await ApiClient.instance.aksi(aksi, parameter);
  final data =
      ((respons['data'] as List?) ?? const []).whereType<Map>().toList();
  // ignore: avoid_print
  print('UAT_READONLY_AKSI=$aksi STATUS=${respons['status']} '
      'JUMLAH=${data.length} TOTAL=${respons['total']}');
  expect(
    data.length,
    greaterThanOrEqualTo(100),
    reason: '$aksi harus mengembalikan minimal 100 data pada UAT live',
  );
  return data.length;
}

Future<int> _pastikanSeratusResepLengkap({
  required bool hanyaMenunggu,
}) async {
  final respons = await ApiClient.instance.aksi(
    'apotik_resep_list',
    {'hanya_menunggu': hanyaMenunggu, 'page_size': 1000},
  );
  final data = ((respons['data'] as List?) ?? const [])
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList();
  final lengkap = data.where(_metadataResepLengkap).length;
  expect(
    lengkap,
    greaterThanOrEqualTo(100),
    reason: 'Daftar resep harus memiliki minimal 100 data klinis lengkap',
  );
  return lengkap;
}

bool _metadataResepLengkap(Map<String, dynamic> resep) => const [
      'pasienNama',
      'nomorRekamMedis',
      'dokterNama',
      'diagnosa',
      'indikasi',
      'asalPelayanan',
      'tanggalResep',
    ].every((field) => (resep[field]?.toString() ?? '').trim().isNotEmpty);

Future<void> _tampilkanMode(
  WidgetTester tester,
  ApotikModePos mode,
  Size ukuran,
  String namaBukti,
) async {
  tester.view.physicalSize = ukuran;
  tester.view.devicePixelRatio = 1;
  final controller = ApotikPosController()..mode = mode;
  await tester.pumpWidget(_app(controller));
  await _tungguKatalog(tester);
  expect(find.textContaining('100 ditampilkan'), findsOneWidget);
  await _ambilGambar(tester, namaBukti);
}

Future<void> _tampilkanTebusResep(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(_app(ApotikPosController()));
  await _tungguKatalog(tester);
  await tester.tap(find.text('Tebus Resep').first);
  await _tungguTeks(tester, 'Resep Menunggu Ditebus');
  expect(find.text('Resep Menunggu Ditebus'), findsOneWidget);
  await _ambilGambar(tester, '05-live-tebus-resep');
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _app(ApotikPosController controller) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        extensions: const [ApotikDesignTokens.light],
      ),
      home: ApotikPosPage(
        key: ValueKey('uat-live-${controller.mode.name}'),
        controller: controller,
        panggil: ApiClient.instance.aksi,
      ),
    );

Future<void> _tungguKatalog(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 500));
      return;
    }
  }
  throw StateError('Katalog belum selesai dimuat setelah 20 detik');
}

Future<void> _tungguTeks(WidgetTester tester, String teks) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.text(teks).evaluate().isNotEmpty) return;
  }
  throw StateError('$teks belum tampil setelah 20 detik');
}

Future<void> _ambilGambar(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak tersedia');
  final image =
      // ignore: deprecated_member_use
      await layer.toImage(tester.binding.renderView.paintBounds, pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal');
  final directory = Directory(_outputDir)..createSync(recursive: true);
  File('${directory.path}\\$nama.png')
      .writeAsBytesSync(data.buffer.asUint8List(), flush: true);
}
