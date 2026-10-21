import 'dart:io';

import 'package:ebisnis/screens/rekap_penjualan_item_dialog.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    Sesi.instance
      ..tenantId = null
      ..userId = '';
  });

  test('kunci laporan memisahkan tenant, pengguna, dan seluruh filter', () {
    Sesi.instance
      ..tenantId = 41
      ..userId = 'Kasir@Toko.id';
    const filter = {
      'tanggal': '2026-10-21',
      'keyword': 'air',
      'kasir': 'kasir-1',
    };
    final a = kunciCacheRekapPenjualanItem(filter);
    expect(a, contains('tenant-41'));
    expect(a, contains('user-kasir@toko.id'));
    expect(
        kunciCacheRekapPenjualanItem({
          'kasir': 'kasir-1',
          'keyword': 'air',
          'tanggal': '2026-10-21',
        }),
        a);
    expect(
        kunciCacheRekapPenjualanItem({...filter, 'keyword': 'roti'}), isNot(a));

    Sesi.instance.tenantId = 42;
    expect(kunciCacheRekapPenjualanItem(filter), isNot(a));
    Sesi.instance
      ..tenantId = 41
      ..userId = 'supervisor';
    expect(kunciCacheRekapPenjualanItem(filter), isNot(a));
  });

  test('laporan membaca salinan lokal sebelum meminta penyegaran server', () {
    final source =
        File('lib/screens/rekap_penjualan_item_dialog.dart').readAsStringSync();
    final bacaLokal = source.indexOf('ambilCacheReferensi(cacheKey)');
    final bacaServer = source.indexOf("aksi('penjualan_item_harian', payload)");
    final simpanLokal = source.indexOf('simpanCacheReferensi(');
    expect(bacaLokal, greaterThanOrEqualTo(0));
    expect(bacaServer, greaterThan(bacaLokal));
    expect(simpanLokal, greaterThan(bacaServer));
    expect(source, contains('PenandaDataTersimpan('));
    expect(source, contains('e is ApiException && e.offline && adaCache'));
    expect(source, contains('Belum ada salinan laporan untuk tanggal ini'));
  });
}
