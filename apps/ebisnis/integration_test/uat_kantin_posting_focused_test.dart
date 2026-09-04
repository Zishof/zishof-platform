import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/laporan_screen.dart';
import 'package:ebisnis/screens/posting_toko_dialog.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:ebisnis/widgets/filter_status_posting.dart';
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

  testWidgets('bukti terfokus 100+ riwayat posting Kantin', (tester) async {
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
      'labelPerangkat': 'UAT-Posting-Terfokus',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

    for (final item in const <(String, String, String)>[
      ('penjualan', 'Posting Penjualan', '05-posting-penjualan'),
      ('hpp', 'Posting HPP', '06-posting-hpp'),
    ]) {
      await _pumpPanel(
        tester,
        PostingKeuanganPanel(jenis: item.$1, judul: item.$2),
      );
      await _tungguFilter(tester, item.$2);
      await _pilihTerposting(tester, item.$2);
      await _ambilGambar(tester, '${item.$3}-telah-diposting-100-plus');
    }

    await _pumpPanel(
      tester,
      const PostingTokoDialog(
        jenis: 'kulakan',
        judul: 'Posting Kulakan',
        inline: true,
      ),
    );
    await _tungguFilter(tester, 'Posting Kulakan');
    await _pilihTerposting(tester, 'Posting Kulakan');
    await _ambilGambar(tester, '07-posting-kulakan-telah-diposting-100-plus');
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

Future<void> _tungguFilter(WidgetTester tester, String judul) async {
  for (var i = 0; i < 240; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(FilterStatusPostingBar).evaluate().isNotEmpty) return;
  }
  fail('$judul tidak menghasilkan kontrol filter status dalam 120 detik.');
}

Future<void> _pilihTerposting(WidgetTester tester, String judul) async {
  final bar = find.byType(FilterStatusPostingBar).last;
  final kontrol = tester.widget<FilterStatusPostingBar>(bar);
  expect(kontrol.jumlahSudah, greaterThanOrEqualTo(100),
      reason:
          '$judul hanya memuat ${kontrol.jumlahSudah} record Telah Diposting.');
  expect(kontrol.jumlahBelum, 0,
      reason: '$judul masih mempunyai record belum diposting.');
  final pilihan = find.descendant(
    of: bar,
    matching: find.textContaining('Telah Diposting'),
  );
  expect(pilihan, findsOneWidget);
  await tester.tap(pilihan);
  await tester.pump(const Duration(seconds: 1));
  expect(find.textContaining('Belum Diposting -'), findsNothing,
      reason: '$judul mencampur data belum diposting pada filter riwayat.');
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
