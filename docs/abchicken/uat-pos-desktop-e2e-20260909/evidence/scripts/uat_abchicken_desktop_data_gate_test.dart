import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/abchicken/operasi_abchicken_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR');

const _proses = <(String, String)>[
  ('outlet_order', 'Pesanan Outlet'),
  ('bom', 'Resep dan BOM'),
  ('procurement_pr', 'Permintaan Pembelian'),
  ('procurement_po', 'Pesanan Pembelian'),
  ('procurement_bast', 'BAST Gudang Pusat'),
  ('procurement_invoice', 'Terima Tagihan Vendor'),
  ('procurement_payment', 'Pembayaran Vendor'),
  ('production', 'Produksi dan Packing'),
  ('shipment', 'Delivery Order dan Pengiriman'),
  ('claim', 'Backorder Retur dan Klaim'),
  ('pos_sale', 'Penjualan POS'),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gate data dan layar operasi AB Chicken melalui POS Desktop',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const contextPath = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(username, isNotEmpty, reason: 'POS_TEST_USERNAME wajib diisi.');
    expect(password, isNotEmpty, reason: 'POS_TEST_PASSWORD wajib diisi.');
    expect(host, isNotEmpty, reason: 'POS_TEST_HOST wajib diisi.');
    expect(_outputDir, isNotEmpty, reason: 'POS_TEST_OUTPUT_DIR wajib diisi.');

    await tester.binding.setSurfaceSize(const Size(2560, 1392));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    CoreDb.configureStorage('abchicken_uat');
    await CoreDb.instance.db;
    addTearDown(() => CoreDb.instance.tutup());

    await ServerConfig.instance
        .simpan(host: host, contextPath: contextPath, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-AB-Chicken-POS-Desktop',
    });
    expect(login['token'], isNotNull,
        reason: 'Login tidak menghasilkan token.');
    await ApiClient.instance.simpanToken(login['token'] as String);

    final ringkasan = await ApiClient.instance
        .aksi('si_restaurant_summary', const <String, dynamic>{});
    final dataRingkasan =
        Map<String, dynamic>.from(ringkasan['data'] as Map? ?? const {});
    expect((dataRingkasan['outlet'] as num?)?.toInt(), 1);
    expect((dataRingkasan['gudangPusat'] as num?)?.toInt(), 1);
    expect((dataRingkasan['produkJual'] as num?)?.toInt(),
        greaterThanOrEqualTo(50));
    expect((dataRingkasan['bahanBaku'] as num?)?.toInt(),
        greaterThanOrEqualTo(100));

    final integritas = await ApiClient.instance
        .aksi('si_restaurant_integrity', const <String, dynamic>{});
    final checks = (integritas['checks'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    expect(checks, isNotEmpty,
        reason: 'Server tidak mengirim pemeriksaan integritas.');
    expect(checks.where((e) => e['lulus'] != true), isEmpty,
        reason:
            'Data tenant belum settle: ada pemeriksaan integritas yang gagal.');

    final catatan = StringBuffer('kode,judul,total,status_gagal,berkas\n');

    await _tampilkan(tester, const OperasiRantaiPasokScreen());
    await _tunggu(tester,
        () => find.text('Seluruh gerbang data UAT lulus').evaluate().isNotEmpty,
        alasan:
            'Ringkasan Desktop belum menyatakan seluruh gerbang data lulus.');
    final ringkasanPath = await _potret(tester, '00-ringkasan-data-settle');
    catatan.writeln(
        'ringkasan,Ringkasan Data Settle,${checks.length},0,$ringkasanPath');

    for (var i = 0; i < _proses.length; i++) {
      final proses = _proses[i];
      final hasil = await ApiClient.instance.aksi(
          'si_restaurant_${proses.$1}_list',
          const <String, dynamic>{'halaman': 1, 'batas': 50});
      final total = (hasil['total'] as num?)?.toInt() ?? 0;
      expect(total, greaterThanOrEqualTo(50),
          reason: '${proses.$2} hanya mempunyai $total record.');

      await _tampilkan(tester, OperasiRantaiPasokScreen(prosesAwal: proses.$1));
      await _beriWaktu(tester, detik: 20);
      if (find.textContaining('$total record').evaluate().isEmpty) {
        final debugPath =
            await _potret(tester, 'debug-${proses.$1}-gagal-muat');
        fail('Daftar ${proses.$2} tidak menampilkan $total record. '
            'Bukti: $debugPath. Teks layar: ${_teksLayar(tester)}');
      }
      expect(find.text('Tidak ada record yang cocok dengan filter.'),
          findsNothing);
      final nomor = (i + 1).toString().padLeft(2, '0');
      final path = await _potret(tester, '$nomor-${proses.$1}-50-record');
      catatan.writeln('${proses.$1},${proses.$2},$total,0,$path');
    }

    await _tampilkan(
        tester, const OperasiRantaiPasokScreen(prosesAwal: 'account'));
    await _tunggu(tester, () => find.text('Ubah akun').evaluate().isNotEmpty,
        alasan: 'Pemetaan akun tidak selesai dimuat.');
    expect(find.textContaining('Belum dipilih'), findsNothing,
        reason: 'Masih ada sumber akun posting yang belum dipetakan.');
    final akunPath = await _potret(tester, '12-sumber-akun-posting');
    catatan.writeln('account,Sumber Akun Posting,3,0,$akunPath');

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);
    await File('${dir.path}\\hasil-gate-data-desktop.csv')
        .writeAsString(catatan.toString(), flush: true);
  });
}

Future<void> _tampilkan(WidgetTester tester, Widget layar) async {
  // Lepaskan state layar sebelumnya. Tanpa langkah ini Flutter mempertahankan
  // State OperasiRantaiPasokScreen karena tipe widget sama, sehingga prosesAwal
  // baru tidak dijalankan dan screenshot tetap menunjukkan tab sebelumnya.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: layar,
  ));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(seconds: 2));
  final nanti = find.text('Nanti');
  if (nanti.evaluate().isNotEmpty) {
    await tester.tap(nanti.last, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _tunggu(WidgetTester tester, bool Function() syarat,
    {required String alasan, int detik = 90}) async {
  final batas = DateTime.now().add(Duration(seconds: detik));
  while (DateTime.now().isBefore(batas)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (syarat()) return;
  }
  fail(alasan);
}

Future<String> _potret(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
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
  expect(file.lengthSync(), greaterThan(10000),
      reason: 'Screenshot $nama terlalu kecil dan mungkin kosong.');
  return file.path;
}

Future<void> _beriWaktu(WidgetTester tester, {required int detik}) async {
  for (var i = 0; i < detik * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

String _teksLayar(WidgetTester tester) {
  final teks = <String>[];
  for (final elemen in find.byType(Text).evaluate()) {
    final nilai = (elemen.widget as Text).data?.trim();
    if (nilai != null && nilai.isNotEmpty && !teks.contains(nilai)) {
      teks.add(nilai);
    }
  }
  return teks.take(30).join(' | ');
}
