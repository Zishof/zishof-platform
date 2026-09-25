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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aksi UAT siklus restoran dijalankan melalui POS Desktop',
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

    await tester.binding.setSurfaceSize(const Size(2560, 1392));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CoreDb.configureStorage('abchicken_uat_actions');
    await CoreDb.instance.db;
    addTearDown(() => CoreDb.instance.tutup());

    await ServerConfig.instance
        .simpan(host: host, contextPath: contextPath, https: https);
    await ApiClient.instance.muatTokenTersimpan();
    if (!ApiClient.instance.sudahLogin) {
      final login = await _aksiBacaDenganRetry('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-AB-Chicken-Aksi-Desktop',
      });
      await ApiClient.instance.simpanToken(login['token'] as String);
    }

    final sebelum = await _ringkasan();
    final jurnalSebelum = (sebelum['jurnalTerposting'] as num).toInt();
    final hasil = StringBuffer(
        'urutan,proses,nomor,status_awal,status_akhir,posting,jurnal_id,hasil\n');

    await _jalankanStatus(
      tester,
      urutan: '01',
      proses: 'outlet_order',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED', 'ALLOCATED'],
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '02',
      proses: 'procurement_pr',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED'],
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '03',
      proses: 'procurement_po',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED'],
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '04',
      proses: 'procurement_bast',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED'],
      posting: true,
      statusSetelahPosting: 'POSTED',
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '05',
      proses: 'procurement_invoice',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED'],
      posting: true,
      statusSetelahPosting: 'POSTED',
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '06',
      proses: 'procurement_payment',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED'],
      posting: true,
      statusSetelahPosting: 'POSTED',
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '07',
      proses: 'production',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED'],
      posting: true,
      statusSetelahPosting: 'POSTED',
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '08',
      proses: 'shipment',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED', 'DELIVERY', 'ARRIVED'],
      posting: true,
      statusSetelahPosting: 'COMPLETED',
      hasil: hasil,
    );
    await _jalankanStatus(
      tester,
      urutan: '09',
      proses: 'claim',
      status: const ['DRAFT', 'SUBMITTED', 'APPROVED', 'RESOLVED'],
      hasil: hasil,
    );

    await _postingPenjualan(tester, hasil);

    final sesudah = await _ringkasan();
    final jurnalSesudah = (sesudah['jurnalTerposting'] as num).toInt();
    expect(jurnalSesudah, jurnalSebelum + 6,
        reason:
            'BAST, tagihan, pembayaran, produksi, pengiriman, dan POS harus menambah enam jurnal.');
    final integritas = await _aksiBacaDenganRetry(
        'si_restaurant_integrity', const <String, dynamic>{});
    final gagal = (integritas['checks'] as List? ?? const [])
        .where((e) => (e as Map)['lulus'] != true)
        .toList();
    expect(gagal, isEmpty,
        reason: 'Integritas tenant gagal setelah siklus transaksi Desktop.');

    await _tampilkan(tester, const OperasiRantaiPasokScreen());
    await _tunggu(tester,
        () => find.text('Seluruh gerbang data UAT lulus').evaluate().isNotEmpty,
        alasan: 'Ringkasan akhir tidak kembali lulus.');
    await _potret(tester, '10-ringkasan-setelah-siklus');

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);
    await File('${dir.path}\\hasil-gate-aksi-desktop.csv')
        .writeAsString(hasil.toString(), flush: true);
  });
}

Future<Map<String, dynamic>> _ringkasan() async {
  final hasil = await _aksiBacaDenganRetry(
      'si_restaurant_summary', const <String, dynamic>{});
  return Map<String, dynamic>.from(hasil['data'] as Map);
}

Future<Map<String, dynamic>?> _cariBarisPertama(
    String proses, String status) async {
  final hasil = await _aksiBacaDenganRetry('si_restaurant_${proses}_list', {
    'status': status,
    'posting': 'BELUM',
    'halaman': 1,
    'batas': 1,
  });
  final data = hasil['data'] as List? ?? const [];
  if (data.isEmpty) return null;
  return Map<String, dynamic>.from(data.first as Map);
}

Future<void> _jalankanStatus(
  WidgetTester tester, {
  required String urutan,
  required String proses,
  required List<String> status,
  required StringBuffer hasil,
  bool posting = false,
  String? statusSetelahPosting,
}) async {
  Map<String, dynamic>? row;
  var indeksAwal = 0;
  for (; indeksAwal < status.length - 1; indeksAwal++) {
    row = await _cariBarisPertama(proses, status[indeksAwal]);
    if (row != null) break;
  }
  expect(row, isNotNull,
      reason:
          'Tidak ada dokumen $proses yang dapat melanjutkan alur ${status.join(' → ')}.');
  final nomor = '${row!['nomor']}';
  await _bukaNomor(tester, proses, nomor);
  await _tunggu(tester, () => find.text(nomor).evaluate().isNotEmpty,
      alasan: '$nomor tidak muncul pada pencarian Desktop.');
  await _potret(
      tester, '$urutan-$proses-${status[indeksAwal].toLowerCase()}');

  for (var i = indeksAwal + 1; i < status.length; i++) {
    final tujuan = status[i];
    await _ubahStatusBaris(tester, nomor, tujuan);
    await _tungguStatusServer(proses, nomor, tujuan);
    await _bukaNomor(tester, proses, nomor);
    await _tunggu(tester, () => _barisBerstatus(nomor, tujuan),
        alasan: '$nomor tidak terlihat berstatus $tujuan di Desktop.');
    if (tujuan == 'APPROVED' ||
        tujuan == 'ALLOCATED' ||
        tujuan == 'DELIVERY' ||
        tujuan == 'ARRIVED' ||
        tujuan == 'RESOLVED') {
      await _potret(tester, '$urutan-$proses-${tujuan.toLowerCase()}');
    }
  }

  var jurnalId = '';
  var akhir = status.last;
  if (posting) {
    jurnalId = await _postingBaris(tester, nomor, urutan, proses);
    akhir = statusSetelahPosting!;
    await _tungguStatusServer(proses, nomor, akhir);
    await _bukaNomor(tester, proses, nomor);
    await _tunggu(tester, () => _barisBerstatus(nomor, akhir),
        alasan: '$nomor tidak terlihat sebagai $akhir setelah posting.');
    await _potret(tester, '$urutan-$proses-posted');
  }

  hasil.writeln(
      '$urutan,$proses,$nomor,${status[indeksAwal]},$akhir,$posting,$jurnalId,LULUS');
}

Future<void> _postingPenjualan(WidgetTester tester, StringBuffer hasil) async {
  const proses = 'pos_sale';
  final daftar = await _aksiBacaDenganRetry(
      'si_restaurant_pos_sale_list', const <String, dynamic>{
    'status': 'DRAF',
    'posting': 'BELUM',
    'cari': 'UAT-AB-POS',
    'halaman': 1,
    'batas': 1,
  });
  final data = daftar['data'] as List? ?? const [];
  expect(data, isNotEmpty,
      reason: 'Tidak ada penjualan outlet AB Chicken yang siap diposting.');
  final row = Map<String, dynamic>.from(data.first as Map);
  final nomor = '${row['nomor']}';
  await _bukaNomor(tester, proses, nomor);
  await _tunggu(tester, () => find.text(nomor).evaluate().isNotEmpty,
      alasan: '$nomor tidak muncul pada daftar POS DRAF.');
  await _potret(tester, '10-pos_sale-draf');
  final jurnalId = await _postingBaris(tester, nomor, '10', proses);
  await _tungguStatusServer(proses, nomor, 'TERPOSTING');
  await _bukaNomor(tester, proses, nomor);
  await _tunggu(tester, () => _barisBerstatus(nomor, 'TERPOSTING'),
      alasan: '$nomor tidak terlihat TERPOSTING setelah posting POS.');
  await _potret(tester, '10-pos_sale-posted');
  hasil.writeln('10,$proses,$nomor,DRAF,TERPOSTING,true,$jurnalId,LULUS');
}

Future<void> _tungguStatusServer(
    String proses, String nomor, String status) async {
  final batas = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(batas)) {
    final hasil = await _aksiBacaDenganRetry(
        'si_restaurant_${proses}_list', <String, dynamic>{
      'cari': nomor,
      'status': status,
      'halaman': 1,
      'batas': 5,
    });
    final cocok = (hasil['data'] as List? ?? const []).any((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return '${row['nomor']}' == nomor && '${row['status']}' == status;
    });
    if (cocok) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('$nomor tidak berstatus $status pada server setelah posting.');
}

Future<Map<String, dynamic>> _aksiBacaDenganRetry(
    String aksi, Map<String, dynamic> body) async {
  Object? galatTerakhir;
  for (var percobaan = 1; percobaan <= 5; percobaan++) {
    try {
      return await ApiClient.instance.aksi(aksi, body);
    } on ApiException catch (e) {
      galatTerakhir = e;
      if (percobaan == 5) rethrow;
      await Future<void>.delayed(Duration(seconds: percobaan));
    }
  }
  throw StateError('Permintaan $aksi gagal: $galatTerakhir');
}

Future<void> _bukaNomor(
    WidgetTester tester, String proses, String nomor) async {
  await _tampilkan(tester, OperasiRantaiPasokScreen(prosesAwal: proses));
  final pencarian = find.byType(TextField);
  expect(pencarian, findsWidgets,
      reason: 'Kotak pencarian $proses tidak ditemukan.');
  await tester.enterText(pencarian.first, nomor);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _beriWaktu(tester, detik: 5);
}

bool _barisBerstatus(String nomor, String status) {
  final card = find.ancestor(of: find.text(nomor), matching: find.byType(Card));
  if (card.evaluate().isEmpty) return false;
  return find
      .descendant(of: card.first, matching: find.text(status))
      .evaluate()
      .isNotEmpty;
}

Future<void> _ubahStatusBaris(
    WidgetTester tester, String nomor, String tujuan) async {
  final card = find.ancestor(of: find.text(nomor), matching: find.byType(Card));
  expect(card, findsWidgets);
  final menu = find.descendant(
      of: card.first, matching: find.byType(PopupMenuButton<String>));
  expect(menu, findsOneWidget,
      reason: 'Tombol perubahan status $nomor tidak ditemukan.');
  await tester.tap(menu, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  final opsi = find.text('Ubah ke $tujuan');
  expect(opsi, findsOneWidget,
      reason: 'Transisi ke $tujuan tidak tersedia untuk $nomor.');
  await tester.tap(opsi, warnIfMissed: false);
  await _tunggu(tester,
      () => find.text('Status $nomor menjadi $tujuan.').evaluate().isNotEmpty,
      alasan: 'Server tidak mengonfirmasi perubahan $nomor ke $tujuan.');
}

Future<String> _postingBaris(
    WidgetTester tester, String nomor, String urutan, String proses) async {
  final card = find.ancestor(of: find.text(nomor), matching: find.byType(Card));
  final tombol =
      find.descendant(of: card.first, matching: find.text('Posting'));
  expect(tombol, findsOneWidget,
      reason: 'Tombol Posting belum aktif untuk $nomor.');
  await tester.tap(tombol, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('Posting ke Akuntansi'), findsOneWidget);
  await _potret(tester, '$urutan-$proses-konfirmasi-posting');
  final dialog = find.byType(AlertDialog);
  final konfirmasi =
      find.descendant(of: dialog, matching: find.text('Posting'));
  expect(konfirmasi, findsOneWidget,
      reason: 'Tombol konfirmasi posting $nomor tidak ditemukan.');
  await tester.tap(konfirmasi, warnIfMissed: false);
  await _tunggu(
      tester,
      () => find
          .textContaining('Posting berhasil. Jurnal ID')
          .evaluate()
          .isNotEmpty,
      alasan: 'Posting $nomor tidak menghasilkan jurnal.');
  final teks = tester
      .widgetList<Text>(find.textContaining('Posting berhasil. Jurnal ID'))
      .map((e) => e.data ?? '')
      .first;
  final cocok = RegExp(r'Jurnal ID\s+(\d+)').firstMatch(teks);
  expect(cocok, isNotNull, reason: 'ID jurnal tidak terbaca untuk $nomor.');
  return cocok!.group(1)!;
}

Future<void> _tampilkan(WidgetTester tester, Widget layar) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: layar,
  ));
  await _beriWaktu(tester, detik: 4);
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

Future<void> _beriWaktu(WidgetTester tester, {required int detik}) async {
  for (var i = 0; i < detik * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

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
