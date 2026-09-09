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
  defaultValue: r'tmp\uat-training-operasional\screenshots',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('laporan training operasional penuh berisi dan clickable',
      (tester) async {
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
      'labelPerangkat': 'UAT-Training-Laporan-eBisnis',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

    const reports = <(String, String, String, String)>[
      (
        'pnj_faktur',
        'Daftar Faktur Penjualan',
        'Laporan Penjualan',
        '14-penjualan-daftar-faktur'
      ),
      (
        'pnj_per_barang',
        'Penjualan per Barang',
        'Laporan Penjualan',
        '15-penjualan-per-barang'
      ),
      (
        'pnj_rincian_barang',
        'Rincian Penjualan per Barang',
        'Laporan Penjualan',
        '16-rincian-penjualan-per-barang'
      ),
      (
        'omzet_transaksi',
        'Detail Omzet Transaksi',
        'Laporan Omzet',
        '17-omzet-transaksi'
      ),
      (
        'omzet_tunai_produk',
        'Omzet Tunai / Non-Saldo per Produk',
        'Laporan Omzet',
        '18-omzet-tunai-per-produk'
      ),
      (
        'omzet_saldo_produk',
        'Omzet Saldo per Produk',
        'Laporan Omzet',
        '19-omzet-saldo-per-produk'
      ),
      (
        'omzet_rekapan',
        'Rekapan Omzet per Toko',
        'Laporan Omzet',
        '20-rekap-omzet-per-toko'
      ),
      (
        'beli_penerimaan',
        'Penerimaan Pembelian',
        'Laporan Pembelian',
        '21-penerimaan-pembelian'
      ),
      (
        'beli_faktur',
        'Daftar Faktur Pembelian',
        'Laporan Pembelian',
        '22-faktur-pembelian'
      ),
      (
        'margin_produk',
        'Margin per Produk',
        'Margin dan Laba',
        '23-margin-per-produk'
      ),
      (
        'margin_kategori',
        'Margin per Kategori',
        'Margin dan Laba',
        '24-margin-per-kategori'
      ),
      (
        'laba_kotor_harian',
        'Laba Kotor Harian',
        'Margin dan Laba',
        '25-laba-kotor-harian'
      ),
    ];

    for (final report in reports) {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: LaporanDetailScreen(item: {
          'id': report.$1,
          'judul': report.$2,
          'ket': '${report.$3} untuk pelatihan operasional An Nahl',
          'satker': false,
        }),
      ));
      await tester.pump(const Duration(milliseconds: 350));

      final button = find.ancestor(
        of: find.text('Tampilkan'),
        matching: find.byType(InkWell),
      );
      expect(button, findsWidgets);
      tester.widget<InkWell>(button.first).onTap?.call();
      await tester.pump(const Duration(milliseconds: 150));
      await _waitForResult(tester, report.$2);

      expect(
        find.text('Tidak ada data untuk filter yang dipilih.'),
        findsNothing,
        reason: '${report.$2} masih kosong.',
      );
      expect(find.textContaining('Gagal'), findsNothing,
          reason: '${report.$2} menampilkan kegagalan.');
      await _shot(tester, '${report.$4}-atas');

      if (report.$1.startsWith('omzet_')) {
        final clickable =
            find.byTooltip('Klik untuk melihat data penghitungannya');
        expect(clickable, findsWidgets,
            reason: '${report.$2} belum menyediakan rincian clickable.');
        await tester.tap(clickable.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));
        await _wait(
          tester,
          () =>
              find.textContaining('Asal Angka:').evaluate().isNotEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty,
          reason: 'Popup rincian ${report.$2} tidak selesai dimuat',
          seconds: 90,
        );
        expect(find.textContaining('Transaksi penyusun angka ini'),
            findsOneWidget);
        await _shot(tester, '${report.$4}-rincian-clickable');
        await tester.tap(find.text('Tutup').last);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await _scrollBottomAndShot(tester, '${report.$4}-bawah');
    }
  });
}

Future<void> _waitForResult(WidgetTester tester, String title) async {
  await _wait(
    tester,
    () {
      final error = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .any((text) => text.contains('Gagal') || text.contains('gagal'));
      if (error) return true;
      final pdf = find.ancestor(
        of: find.text('PDF'),
        matching: find.byType(InkWell),
      );
      return pdf.evaluate().isNotEmpty &&
          tester.widget<InkWell>(pdf.first).onTap != null &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty;
    },
    reason: '$title tidak selesai dimuat',
    seconds: 180,
  );
}

Future<void> _scrollBottomAndShot(WidgetTester tester, String name) async {
  final scrollables = find.descendant(
    of: find.byType(LaporanDetailScreen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  expect(scrollables, findsWidgets);
  final state = tester.state<ScrollableState>(scrollables.first);
  if (state.position.maxScrollExtent > 0) {
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 700));
    expect(state.position.pixels, closeTo(state.position.maxScrollExtent, 1));
  }
  await _shot(tester, name);
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  int seconds = 45,
}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) return;
  }
  throw StateError(reason);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
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
  if (data == null) throw StateError('Screenshot $name gagal');
  final directory = Directory(_outputDir);
  await directory.create(recursive: true);
  await File('${directory.path}\\$name.png')
      .writeAsBytes(data.buffer.asUint8List(), flush: true);
}
