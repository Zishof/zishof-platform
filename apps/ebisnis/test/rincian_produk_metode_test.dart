import 'dart:async';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:ebisnis/services/rincian_produk_metode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(int id, String metode, {int qty = 1}) => {
      'idTransaksi': id,
      'nomorNota': 'NOTA-$id',
      'produkKode': 'P1',
      'produkNama': 'Produk Uji',
      'metode': metode,
      'qty': qty,
      'total': qty * 1000,
      'satuan': 'Pcs',
    };

// compute memakai isolate nyata; beri event loop nyata kesempatan menyelesaikan
// pekerjaan sebelum menunggu animasi Flutter di zona fake-async.
Future<void> pumpReport(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (ready() && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Laporan tidak selesai dimuat dalam batas waktu tes.');
}

void main() {
  test('tiga kelompok utama dan variasi QRIS lama dikelompokkan', () {
    expect(metodeRincianProduk.take(3),
        ['Voucher Santri', 'Voucher Pejuang', kelompokTunaiTransferQris]);
    expect(kelompokMetodeProduk(' voucher   pejuang '), 'Voucher Pejuang');
    expect(kelompokMetodeProduk('VOUCHER SANTRI'), 'Voucher Santri');
    for (final nama in [
      'Transfer BSI',
      'QRIS BCA',
      'QRS - BSI',
      'Transfer/QRIS',
      'TF BSI',
      'Tunai/Transfer/QRIS',
      'Tunai',
      'Cash',
    ]) {
      expect(kelompokMetodeProduk(nama), kelompokTunaiTransferQris);
    }
  });

  test('non tunai, kosong dan metode lain tidak ditebak sebagai tunai', () {
    for (final nama in [
      null,
      '',
      '-',
      'Non Tunai',
      'Kasbon Divisi',
      'Reward'
    ]) {
      expect(kelompokMetodeProduk(nama), 'Lainnya / belum diketahui');
    }
  });

  test('split tidak masuk dua kelompok dan rincian asli tidak diubah', () {
    final split = row(1, 'Voucher Pejuang Rp 5.000 + Tunai Rp 1.000');
    expect(kelompokMetodeProduk(split['metode']), 'Campuran (split)');
    expect(
        saringMetodeRincianProduk([split], kelompokTunaiTransferQris), isEmpty);
    expect(saringMetodeRincianProduk([split], 'Voucher Pejuang'), isEmpty);
    expect(saringMetodeRincianProduk([split], 'Campuran (split)'), [split]);
    expect(split['metode'], contains('Rp 5.000'));
  });

  test('produk sama beda kelompok terpisah, Tunai QRIS dan Transfer digabung',
      () {
    final rows = [
      row(1, 'Tunai'),
      row(2, 'Voucher Santri', qty: 2),
      row(3, 'QRIS BSI', qty: 3),
      row(4, 'Transfer', qty: 4),
      row(5, 'Voucher Pejuang', qty: 5),
    ];
    final hasil = rekapProdukDariRincian(rows, pisahMetode: true);
    expect(hasil, hasLength(3));
    final reguler =
        hasil.singleWhere((r) => r['metode'] == kelompokTunaiTransferQris);
    expect(reguler['qty'], 8);
    expect(reguler['total'], 8000);
    expect(reguler['jumlahTransaksi'], 3);
    expect(hasil.singleWhere((r) => r['metode'] == 'Voucher Santri')['qty'], 2);
    expect(
        hasil.singleWhere((r) => r['metode'] == 'Voucher Pejuang')['qty'], 5);
    expect(hasil.fold<num>(0, (n, r) => n + (r['total'] as num)), 15000);
  });

  test('filter diterapkan sebelum menghitung rekap dan paginasi', () {
    final data = [
      for (var i = 0; i < 25; i++)
        row(i, i.isEven ? 'Tunai' : 'Voucher Pejuang')
    ];
    final hasil = susunTampilanRincianProduk(
        {'rows': data, 'metode': kelompokTunaiTransferQris, 'halaman': 2});
    expect(hasil['total'], 13);
    expect(hasil['data'], hasLength(3));
    expect((hasil['rekap'] as List).single['qty'], 13);
    final reset = susunTampilanRincianProduk({'rows': data, 'metode': ''});
    expect(reset['total'], 25);
  });

  test('paginasi tidak memotong item dari nota yang sama', () {
    final data = [
      for (var i = 1; i <= 11; i++) ...[row(i, 'Tunai'), row(i, 'Tunai')]
    ];
    expect(halamanRincianProduk(data, 1, 10)['data'], hasLength(20));
    expect(halamanRincianProduk(data, 2, 10)['data'], hasLength(2));
  });

  test('pengambilan melintasi halaman kosong dan menjaga filter periode',
      () async {
    final pages = <int>[];
    final hasil = await ambilSemuaBarisRincianProduk({'tglMulai': '2026-09-17'},
        ambilHalaman: (body, cache) async {
      expect(body['tglMulai'], '2026-09-17');
      expect(body['pageSize'], 100);
      final page = body['page'] as int;
      pages.add(page);
      return {
        'total': 201,
        'data': page == 2 ? <Map<String, dynamic>>[] : [row(page, 'Tunai')]
      };
    });
    expect(pages, [1, 2, 3]);
    expect(hasil.baris, hasLength(2));
    expect(hasil.terpotong, isFalse);
  });

  test('cache dipisahkan menurut akses, toko, server dan halaman', () {
    String key(
            {String user = 'a',
            int toko = 1,
            String server = 'https://a',
            int page = 1,
            bool admin = false}) =>
        kunciCacheRincianProduk({'page': page},
            server: server,
            user: user,
            tenant: 1,
            toko: toko,
            admin: admin,
            supervisor: false);
    expect({
      key(),
      key(user: 'b'),
      key(toko: 2),
      key(server: 'https://b'),
      key(page: 2),
      key(admin: true)
    }, hasLength(6));
  });

  testWidgets(
      'dropdown menyaring rekap dan ekspor, rincian membawa metode asli',
      (tester) async {
    tester.view.reset();
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<RincianProdukTabState>();
    final data = [
      row(1, 'Tunai'),
      row(2, 'Voucher Pejuang', qty: 2),
      row(3, 'QRIS BSI', qty: 3)
    ];
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RincianProdukTab(
                key: key,
                statistik: null,
                pemuat: (filter, cache) async {
                  calls.add(cache);
                  return HasilBarisRincian(data, false, dariCache: cache);
                }))));
    await pumpReport(tester, () => calls.length >= 2);
    expect(calls.take(2), [true, false]);
    await tester.tap(find.byKey(const Key('filter-metode-rincian-produk')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voucher Pejuang').last);
    await pumpReport(tester, () => calls.length >= 4);
    final report =
        await tester.runAsync(() => key.currentState!.laporanUntukTest());
    expect(report!.rows, hasLength(1));
    expect(report.rows.single['metode'], 'Voucher Pejuang');
    expect(report.rows.single['qty'], 2);
    expect(report.subtitle, contains('Metode: Voucher Pejuang'));
    expect(report.columns.map((c) => c.key), contains('metode'));
    await tester.tap(find.text('Rincian'));
    await tester.pumpAndSettle();
    final detail =
        await tester.runAsync(() => key.currentState!.laporanUntukTest());
    expect(detail!.rows.single['nomorNota'], 'NOTA-2');
    expect(detail.rows.single['metode'], 'Voucher Pejuang');
    await tester.tap(find.byKey(const Key('filter-metode-rincian-produk')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kelompokTunaiTransferQris).last);
    await pumpReport(tester, () => calls.length >= 6);
    final gabungan =
        await tester.runAsync(() => key.currentState!.laporanUntukTest());
    expect(gabungan!.rows, hasLength(2));
    expect(gabungan.rows.map((r) => r['metode']), ['Tunai', 'QRIS BSI']);
    await tester.tap(find.text('Rekap per produk'));
    await tester.pumpAndSettle();
    final rekapGabungan =
        await tester.runAsync(() => key.currentState!.laporanUntukTest());
    expect(rekapGabungan!.rows, hasLength(1));
    expect(rekapGabungan.rows.single['qty'], 4);
    expect(rekapGabungan.rows.single['total'], 4000);
    expect(rekapGabungan.rows.single['metode'], kelompokTunaiTransferQris);
    expect(tester.takeException(), isNull);
  });

  test(
      'split dalam kelompok reguler digabung, lintas kelompok tidak digandakan',
      () {
    expect(kelompokMetodeProduk('Tunai Rp 1.000 + QRIS BSI Rp 2.000'),
        kelompokTunaiTransferQris);
    expect(kelompokMetodeProduk('Transfer + QRIS'), kelompokTunaiTransferQris);
    for (final label in [
      'Voucher Santri + Voucher Pejuang',
      'Tunai + Reward',
      'split',
      'Tunai +'
    ]) {
      expect(kelompokMetodeProduk(label), 'Campuran (split)');
    }
  });

  testWidgets('salinan lokal tampil saat refresh gagal tanpa menghapus laporan',
      (tester) async {
    final network = Completer<HasilBarisRincian>();
    final key = GlobalKey<RincianProdukTabState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RincianProdukTab(
                key: key,
                statistik: null,
                pemuat: (filter, cache) async {
                  if (cache) {
                    return HasilBarisRincian([row(1, 'Tunai')], false,
                        dariCache: true);
                  }
                  return network.future;
                }))));
    await pumpReport(
        tester, () => find.text('Produk Uji').evaluate().isNotEmpty);
    expect(find.text('Produk Uji'), findsOneWidget);
    expect(find.textContaining('Salinan lokal'), findsOneWidget);
    network.completeError(ApiException('Server gagal', statusHttp: 503));
    await tester.pumpAndSettle();
    expect(find.text('Produk Uji'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
