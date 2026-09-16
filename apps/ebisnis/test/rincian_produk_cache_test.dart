import 'dart:io';

import 'package:core_db/core_db.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:ebisnis/services/rincian_produk_cache.dart';
import 'package:ebisnis/services/rincian_produk_metode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('uat-rincian-metode-');
    CoreDb.configureStorage('uat_rincian_metode');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, (call) async => root.path);
  });
  tearDownAll(() async {
    await CoreDb.instance.tutup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, null);
    // Hanya direktori sementara yang dibuat tes ini.
    await root.delete(recursive: true);
  });

  test('SQLite memfilter sebelum paginasi, ekspor seluruh halaman dan restart',
      () async {
    final rows = [
      for (var i = 1; i <= 25; i++)
        {
          'idTransaksi': i,
          'nomorNota': 'NOTA-$i',
          'produkKode': 'P1',
          'produkNama': 'Produk Uji',
          'satuan': 'Pcs',
          'qty': 2,
          'total': 2000,
          'metode': i.isOdd ? 'Tunai' : 'Voucher Pejuang',
        }
    ];
    await RincianProdukCache.simpan(
        'toko-a', snapshotSqlRincianProduk(HasilBarisRincian(rows, false)));
    var hasil = (await RincianProdukCache.baca(
        'toko-a', kelompokTunaiTransferQris,
        halaman: 2))!;
    expect(hasil['total'], 13);
    expect(hasil['data'], hasLength(3));
    expect((hasil['rekap'] as List).single['total'], 26000);
    expect((hasil['rekap'] as List).single['qty'], 26);
    expect((hasil['rekap'] as List).single['jumlahTransaksi'], 13);
    hasil = (await RincianProdukCache.baca('toko-a', kelompokTunaiTransferQris,
        ekspor: true))!;
    expect(hasil['rows'], hasLength(13));
    final kosong = (await RincianProdukCache.baca('toko-a', 'Voucher Santri'))!;
    expect(kosong['rows'], isEmpty);
    expect(kosong['rekap'], isEmpty);
    expect(await RincianProdukCache.baca('toko-b', ''), isNull);
    await CoreDb.instance.tutup();
    expect((await RincianProdukCache.baca('toko-a', ''))!['total'], 25);
    await RincianProdukCache.simpan('toko-a',
        snapshotSqlRincianProduk(HasilBarisRincian([rows.first], false)));
    hasil = (await RincianProdukCache.baca('toko-a', '', halaman: 2))!;
    expect(hasil['total'], 1);
    expect(hasil['halaman'], 1);
    expect(hasil['data'], hasLength(1));
  });

  test('rekap SQL sama dengan rekap referensi, termasuk split dan kode lama',
      () async {
    final rows = [
      {
        'idTransaksi': 1,
        'produkKode': 'EB260917-AN000123',
        'produkNama': 'Produk',
        'metode': 'QRIS BSI',
        'qty': 2,
        'total': 2000
      },
      {
        'idTransaksi': 2,
        'produkKode': 'AN000123',
        'produkNama': 'Produk',
        'metode': 'Transfer BSI',
        'qty': 3,
        'total': 3000
      },
      {
        'idTransaksi': 3,
        'produkKode': 'AN000123',
        'produkNama': 'Produk',
        'metode': 'Voucher Santri Rp 500 + Tunai Rp 500',
        'qty': 1,
        'total': 1000
      },
    ];
    await RincianProdukCache.simpan(
        'split', snapshotSqlRincianProduk(HasilBarisRincian(rows, false)));
    final hasil = (await RincianProdukCache.baca('split', ''))!;
    final rekap = (hasil['rekap'] as List).cast<Map<String, dynamic>>();
    final acuan = rekapProdukDariRincian(rows, pisahMetode: true);
    expect(rekap, hasLength(acuan.length));
    for (var i = 0; i < acuan.length; i++) {
      for (final kolom in [
        'produkKode',
        'metode',
        'qty',
        'total',
        'jumlahTransaksi'
      ]) {
        expect(rekap[i][kolom], acuan[i][kolom]);
      }
    }
    expect(
        (await RincianProdukCache.baca(
            'split', kelompokTunaiTransferQris))!['total'],
        2);
  });

  test(
      'rekap besar berhalaman, ekspor utuh dan respons rusak tidak menimpa cache',
      () async {
    final rows = [
      for (var i = 0; i < 51; i++)
        {
          'idTransaksi': i,
          'produkKode': 'P$i',
          'produkNama': 'Produk $i',
          'metode': 'Voucher Santri',
          'qty': 1,
          'total': 1000,
        }
    ];
    await RincianProdukCache.simpan(
        'besar', snapshotSqlRincianProduk(HasilBarisRincian(rows, false)));
    final page = (await RincianProdukCache.baca('besar', '', halamanRekap: 2))!;
    expect(page['rekap'], hasLength(1));
    expect(page['totalRekap'], 51);
    expect(page['nilaiRekap'], 51000);
    expect((await RincianProdukCache.baca('besar', '', ekspor: true))!['rekap'],
        hasLength(51));
    await expectLater(
        ambilSemuaBarisRincianProduk({},
            ambilHalaman: (_, __) async => {'status': '00'}),
        throwsFormatException);
    expect((await RincianProdukCache.baca('besar', ''))!['total'], 51);
  });
}
