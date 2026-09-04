import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue:
      r'C:\opt\AIS\ais\src\main\docs\pos\manual-uat-kantin-volume\screenshots-uat-e2e-v13423-final',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('enam laporan keuangan penuh dan berisi', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await tester.binding.setSurfaceSize(const Size(2560, 1392));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Laporan-Keuangan-Terfokus',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

    const laporan = <(String, String, String)>[
      (
        'akn_laba_rugi',
        'Laba Rugi (Berbasis Jurnal Akuntansi)',
        '24-laba-rugi'
      ),
      ('akn_neraca', 'Neraca (Berbasis Jurnal Akuntansi)', '25-neraca'),
      ('akn_arus_kas', 'Arus Kas (Berbasis Jurnal Akuntansi)', '26-arus-kas'),
      ('akn_jurnal', 'Keseluruhan Jurnal (Jurnal Umum)', '27-jurnal-umum'),
      ('akn_buku_besar', 'Rincian Buku Besar (per Akun)', '28-buku-besar'),
      (
        'akn_neraca_saldo',
        'Neraca Percobaan (Neraca Saldo)',
        '29-neraca-saldo'
      ),
    ];

    for (final item in laporan) {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: LaporanDetailScreen(item: {
          'id': item.$1,
          'judul': item.$2,
          'ket': 'Laporan berbasis jurnal terposting — UAT Kantin',
          'satker': false,
        }),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await _aturSampaiTanggal30(tester);
      final tombol = find.ancestor(
        of: find.text('Tampilkan'),
        matching: find.byType(InkWell),
      );
      expect(tombol, findsWidgets);
      final aksi = tester.widget<InkWell>(tombol.first).onTap;
      expect(aksi, isNotNull);
      aksi!.call();
      await tester.pump(const Duration(milliseconds: 100));
      await _tungguHasil(tester, item.$2);
      expect(
          find.text('Tidak ada data untuk filter yang dipilih.'), findsNothing,
          reason: '${item.$2} masih kosong.');
      expect(find.textContaining('Gagal'), findsNothing,
          reason: '${item.$2} menampilkan kegagalan.');
      await _ambilGambar(tester, '${item.$3}-full-atas');
      await _keBawahDanFoto(tester, '${item.$3}-full-bawah');
    }
  });
}

Future<void> _aturSampaiTanggal30(WidgetTester tester) async {
  final label = find.text('Tanggal Sampai');
  expect(label, findsOneWidget);
  final ink = find.ancestor(of: label, matching: find.byType(InkWell)).first;
  await tester.tap(ink);
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(find.text('30').last);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> _tungguHasil(WidgetTester tester, String judul) async {
  for (var i = 0; i < 360; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    final galat = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .where((s) => s.contains('Gagal') || s.contains('gagal'))
        .toList();
    if (galat.isNotEmpty) fail('$judul gagal dimuat: ${galat.join(' | ')}');
    final pdf = find.ancestor(
      of: find.text('PDF'),
      matching: find.byType(InkWell),
    );
    final masihCache = find
        .textContaining('Menampilkan salinan tersimpan')
        .evaluate()
        .isNotEmpty;
    final masihMemuat =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (pdf.evaluate().isNotEmpty &&
        tester.widget<InkWell>(pdf.first).onTap != null &&
        !masihCache &&
        !masihMemuat) {
      return;
    }
  }
  fail('$judul tidak selesai dimuat dalam 180 detik.');
}

Future<void> _keBawahDanFoto(WidgetTester tester, String nama) async {
  final scrollable = find.descendant(
    of: find.byType(LaporanDetailScreen),
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  expect(scrollable, findsWidgets);
  final state = tester.state<ScrollableState>(scrollable.first);
  if (state.position.maxScrollExtent > 0) {
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.position.pixels, closeTo(state.position.maxScrollExtent, 1));
  }
  await _ambilGambar(tester, nama);
}

Future<void> _ambilGambar(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak tersedia');
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal');
  final dir = Directory(_outputDir);
  await dir.create(recursive: true);
  await File('${dir.path}\\$nama.png')
      .writeAsBytes(data.buffer.asUint8List(), flush: true);
}
