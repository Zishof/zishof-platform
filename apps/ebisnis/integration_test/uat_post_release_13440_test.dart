import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/app_variant.dart';
import 'package:ebisnis/screens/anggota/histori_pelunasan_screen.dart';
import 'package:ebisnis/screens/anggota/tab_mutasi_hutang.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:ebisnis/screens/produk_screen.dart';
import 'package:ebisnis/services/master_offline.dart';
import 'package:ebisnis/services/rincian_produk_metode.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/services/sinkron_stok_opname.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:ebisnis/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const output = String.fromEnvironment('UAT_OUTPUT',
    defaultValue:
        r'E:\CodexBuild\backoffice-faktur-pdf-20260914\output\uat-1.34.40-20260917');
final evidence = <Map<String, dynamic>>[];
final evidenceView = GlobalKey();

// UAT lokal: layar produksi, HTTP loopback, SQLite namespace khusus, data fiktif.
// Tidak menggunakan main/login atau kredensial dan server toko.
void main({bool headless = false}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('UAT pascarilis laporan HPP dan pelunasan', (tester) async {
    await initializeDateFormatting('id_ID');
    SharedPreferences.setMockInitialValues({});
    if (headless || const bool.fromEnvironment('UAT_HEADLESS')) {
      final temporary = await Directory.systemTemp.createTemp('uat-layar-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => temporary.path);
    }
    CoreDb.configureStorage(
        'uat_13440_${AppVariant.kode}_${DateTime.now().millisecondsSinceEpoch}');
    final fixture = _Fixture();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(fixture.handle);
    ServerConfig.instance
      ..host = '127.0.0.1:${server.port}'
      ..contextPath = 'uat'
      ..https = false;
    Sesi.instance
      ..userId = 'uat-local'
      ..tokoId = 1
      ..tokoNama = 'TOKO UAT ${AppVariant.kode}'
      ..isAdmin = true
      ..bolehEntryPelunasanPiutang = true;
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() async {
      SinkronStokOpname.berhenti();
      MasterOffline.hentikanTimer();
      await server.close(force: true);
      await Directory('$output/${AppVariant.kode}').create(recursive: true);
      await File('$output/${AppVariant.kode}/skenario.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    });

    final reportKey = GlobalKey<RincianProdukTabState>();
    await mount(
        tester,
        Scaffold(
            appBar: AppBar(title: const Text('Rincian Produk')),
            body: RincianProdukTab(key: reportKey, statistik: null)));
    await until(tester, () => find.text('UAT MINUMAN').evaluate().isNotEmpty);
    for (final entry in [
      ('Voucher Santri', 2, 14000),
      ('Voucher Pejuang', 3, 21000),
      (kelompokTunaiTransferQris, 6, 42000),
    ]) {
      await tester.tap(find.byKey(const Key('filter-metode-rincian-produk')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1).last);
      await until(tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.pump(const Duration(seconds: 1));
      final report = await reportKey.currentState!.laporanUntukTest();
      expect(report.rows, hasLength(1));
      expect(report.rows.single['qty'], entry.$2);
      expect(report.rows.single['total'], entry.$3);
      expect(report.rows.single['metode'], entry.$1);
      await shot(tester, 'rekap-${entry.$2}', 'Rekap ${entry.$1}',
          'Satu produk, qty ${entry.$2}, total ${entry.$3}; data ekspor sama dengan filter.');
    }
    await tester.tap(find.text('Rincian'));
    await tester.pumpAndSettle();
    final detail = await reportKey.currentState!.laporanUntukTest();
    expect(detail.rows, hasLength(3));
    expect(detail.rows.map((r) => r['metode']).toSet(),
        {'Tunai', 'Transfer BSI', 'QRIS BSI'});
    await shot(tester, 'rincian-reguler', 'Rincian metode asli',
        'Tunai Transfer dan QRIS tetap dapat ditelusuri per nota.');

    await mount(tester, const ProdukScreen());
    await until(tester, () => find.text('UAT MINUMAN').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('5.520'), findsWidgets);
    await shot(tester, 'hpp-awal', 'HPP sebelum penyuntingan',
        'HPP awal Rp5.520 dibaca dari katalog dan SQLite.');
    await tester.tap(find.text('UAT MINUMAN').first);
    await until(
        tester, () => find.text('Identitas Produk').evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    final hpp = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is AppFormTextField && w.label == 'Harga Beli'),
        matching: find.byType(TextFormField));
    await lihat(tester, hpp);
    await tester.enterText(hpp, '6000');
    final stok = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is AppFormTextField && w.label == 'Stok'),
        matching: find.byType(TextFormField));
    await lihat(tester, stok);
    await tester.enterText(stok, '7');
    await shot(tester, 'hpp-edit', 'Edit HPP produk',
        'Harga beli diubah menjadi Rp6.000 dan stok 7 pada form produk asli.');
    await lihat(tester, find.text('Simpan'));
    await tester.tap(find.text('Simpan'));
    await until(
        tester,
        () =>
            fixture.product['hargaBeli'] == 6000 &&
            find.text('Identitas Produk').evaluate().isEmpty);
    await tester.pump(const Duration(seconds: 2));
    MasterOffline.revisiBaris.value++;
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('6.000'), findsWidgets);
    expect(fixture.product['stok'], 7);
    await shot(tester, 'hpp-sesudah-simpan', 'HPP setelah simpan dan refresh',
        'HPP tetap Rp6.000 sesudah callback cache lokal dan penyegaran.');
    await mount(
        tester, const Scaffold(body: Text('Memulai ulang pembacaan lokal')));
    SinkronStokOpname.berhenti();
    MasterOffline.hentikanTimer();
    await CoreDb.instance.tutup();
    fixture.offline = true;
    await mount(tester, const ProdukScreen());
    await until(
        tester, () => find.textContaining('6.000').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('6.000'), findsWidgets);
    final cachedProduct =
        (await CoreDb.instance.produkCacheResolveByIds([198])).single;
    expect(cachedProduct['stok'], 7);
    await shot(tester, 'hpp-restart-offline', 'HPP setelah buka ulang offline',
        'Koneksi fixture HTTP 503; SQLite tetap menampilkan HPP Rp6.000.');
    fixture.offline = false;

    // Simpan pelunasan melalui form dan outbox produksi ke server loopback.
    await mount(
        tester,
        Scaffold(
            appBar: AppBar(title: const Text('Mutasi Piutang')),
            body: Builder(
                builder: (context) => Center(
                    child: FilledButton(
                        onPressed: () => showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => const FormPelunasanPiutang(
                                idAnggotaAwal: 7,
                                namaAnggotaAwal: 'PELANGGAN UAT')),
                        child: const Text('Entri Pelunasan Piutang'))))));
    await tester.tap(find.text('Entri Pelunasan Piutang'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tanggal-pelunasan')));
    await tester.pumpAndSettle();
    await shot(tester, 'pelunasan-kalender', 'Pilihan tanggal pelunasan',
        'Kalender menerima tanggal lampau dan membatasi tanggal mendatang.');
    final tanggal = DateTime.now().subtract(const Duration(days: 2));
    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(tanggal);
    await tester.pumpAndSettle();
    final nominal = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is AppFormTextField && w.label == 'Nominal *'),
        matching: find.byType(TextFormField));
    await lihat(tester, nominal);
    await tester.enterText(nominal, '15000');
    final ket = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is AppFormTextField && w.label == 'Keterangan'),
        matching: find.byType(TextFormField));
    await tester.enterText(ket, 'Cicilan UAT tanggal lampau');
    await shot(tester, 'pelunasan-entri', 'Entri pembayaran bertanggal',
        'Nominal Rp15.000, pelanggan UAT, tanggal dua hari sebelumnya.');
    await lihat(tester, find.text('Simpan'));
    await tester.tap(find.text('Simpan'));
    await until(
        tester,
        () =>
            fixture.payments.length == 1 &&
            find.byType(FormPelunasanPiutang).evaluate().isEmpty);
    expect(fixture.localBeforeNetwork, isTrue);
    expect(
        DateUtils.isSameDay(
            DateTime.parse('${fixture.payments.single['waktu']}'), tanggal),
        isTrue);

    await mount(
        tester,
        HistoriPelunasanScreen(
            dari: DateTime(tanggal.year, tanggal.month, 1),
            sampai: DateTime.now(),
            idAnggota: 7,
            namaAnggota: 'PELANGGAN UAT'));
    await until(
        tester,
        () =>
            find.textContaining('1 pembayaran • Total').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('15.000'), findsWidgets);
    await shot(tester, 'histori-online', 'Histori pembayaran terkonfirmasi',
        'Tanggal pelanggan nominal keterangan dan total sesuai entri. Penambahan piutang tidak masuk histori pembayaran.');
    fixture.offline = true;
    await tester.tap(find.text('Muat Ulang'));
    await until(
        tester,
        () => find
            .textContaining('Menampilkan salinan lokal')
            .evaluate()
            .isNotEmpty);
    expect(find.textContaining('1 pembayaran • Total'), findsOneWidget);
    await shot(tester, 'histori-offline', 'Histori tetap tersedia saat offline',
        'Server fixture HTTP 503; pembayaran tetap terbaca, disertai peringatan salinan lokal.');
    expect(tester.takeException(), isNull);
    await mount(tester, const Scaffold(body: Text('UAT lokal selesai')));
  });
}

Future<void> mount(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (_, child) => RepaintBoundary(
            key: evidenceView,
            child: Column(children: [
              Material(
                  color: const Color(0xffe8edf2),
                  child: SizedBox(
                      height: 32,
                      child: Center(
                          child: Text(
                              '${AppVariant.namaAplikasi} 1.34.40 build 203 | UAT lokal | Data uji')))),
              Expanded(child: child!),
            ]),
          ),
      home: home));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(ready(), isTrue, reason: 'Batas tunggu UAT 60 detik');
}

Future<void> lihat(WidgetTester tester, Finder finder) async {
  // Form fields are already built inside a vertical scroll view. Text fields
  // also contain horizontal Scrollables; never drag those to reveal the form.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 300,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last,
        maxScrolls: 35);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> shot(
    WidgetTester tester, String name, String title, String actual) async {
  await tester.pump(const Duration(milliseconds: 300));
  final boundary =
      evidenceView.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final dir = Directory('$output/${AppVariant.kode}');
  await dir.create(recursive: true);
  await File('${dir.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  evidence.add({
    'id': name,
    'judul': title,
    'hasil': actual,
    'status': 'LULUS',
    'screenshot': '$name.png'
  });
  debugPrint('UAT LULUS ${AppVariant.kode}: $name');
}

class _Fixture {
  bool offline = false;
  bool localBeforeNetwork = false;
  final payments = <Map<String, dynamic>>[];
  final product = <String, dynamic>{
    'id': 198,
    'kode': 'UAT198',
    'nama': 'UAT MINUMAN',
    'hargaBeli': 5520,
    'hargaBeliManual': true,
    'hargaJual': 7000,
    'stok': 4,
    'aktif': true,
    'jenisItem': 'JUAL',
    'kategoriId': 1,
    'kategoriNama': 'Minuman',
    'satuanId': 1,
    'satuanNama': 'Pcs',
    'satuanPembelianId': 1,
    'satuanPembelianNama': 'Pcs'
  };
  Future<void> handle(HttpRequest request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join())
        as Map<String, dynamic>;
    request.response.headers.contentType = ContentType.json;
    if (offline) {
      request.response.statusCode = 503;
      request.response.write(
          jsonEncode({'status': '91', 'description': 'Simulasi offline UAT'}));
      await request.response.close();
      return;
    }
    Map<String, dynamic> response = {'status': '00', 'data': []};
    switch (body['action']) {
      case 'katalog':
        response.addAll({
          'produk': [product],
          'total': 1
        });
      case 'jenis_produk_list':
        response['data'] = [
          {'id': 1, 'nama': 'Minuman'}
        ];
      case 'uom_list':
        response['data'] = [
          {'id': 1, 'nama': 'Pcs', 'kategori': 'UNIT', 'aktif': true}
        ];
      case 'produk_simpan':
        if (body['id'] != 198) throw StateError('ID produk UAT tidak sesuai');
        product['hargaBeli'] = body['harga_beli'];
        if (body.containsKey('stok')) product['stok'] = body['stok'];
        response.addAll({'id': 198, 'stok': product['stok']});
      case 'laporan_rincian_produk':
        final methods = [
          'Voucher Santri',
          'Voucher Pejuang',
          'Tunai',
          'Transfer BSI',
          'QRIS BSI'
        ];
        final qty = [2, 3, 1, 2, 3];
        response.addAll({
          'total': 5,
          'data': [
            for (var i = 0; i < 5; i++)
              {
                'idTransaksi': i + 1,
                'nomorNota': 'UAT-${i + 1}',
                'produkKode': 'UAT198',
                'produkNama': 'UAT MINUMAN',
                'satuan': 'Pcs',
                'qty': qty[i],
                'total': qty[i] * 7000,
                'hargaSatuan': 7000,
                'waktu': '2026-09-17 10:00:00',
                'kasir': 'KASIR UAT',
                'metode': methods[i]
              }
          ]
        });
      case 'hutang_bayar_simpan':
        final pending = await CoreDb.instance.outboxMasterPending();
        localBeforeNetwork = pending.any((r) =>
            jsonDecode('${r['payload_json']}')['client_mutation_id'] ==
            body['client_mutation_id']);
        payments.add({
          'barisId': 'C1',
          'idAnggota': 7,
          'namaAnggota': 'PELANGGAN UAT',
          'waktu': body['waktu'],
          'berkurang': body['nominal'],
          'bertambah': 0,
          'keterangan': body['keterangan']
        });
        response['id'] = 1;
      case 'mutasi_hutang_list':
        response.addAll({
          'data': [
            {'barisId': 'H11', 'bertambah': 50000},
            ...payments
          ],
          'total': payments.length + 1
        });
    }
    request.response.write(jsonEncode(response));
    await request.response.close();
  }
}
