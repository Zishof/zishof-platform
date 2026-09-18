import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Kontrak UI Fitur Produk Paket di produk_screen.dart', () {
    late String produkScreenCode;

    setUpAll(() {
      produkScreenCode = File('lib/screens/produk_screen.dart').readAsStringSync();
    });

    test('Filter bilah atas memiliki segmen PAKET dengan label Produk Paket', () {
      expect(produkScreenCode, contains("value: 'PAKET'"));
      expect(produkScreenCode, contains("Text('Produk Paket')"));
    });

    test('Form Jenis Item memiliki segmen PAKET', () {
      expect(
        produkScreenCode.contains("ButtonSegment(value: 'PAKET', label: Text('Produk Paket'))") ||
        produkScreenCode.contains("value: 'PAKET'"),
        isTrue,
      );
    });

    test('Dialog pemilih komponen _tambahKomponenPaket memfilter status JUAL', () {
      expect(produkScreenCode, contains('_tambahKomponenPaket'));
      expect(produkScreenCode, contains("p.jenisItem == 'JUAL' || p.jenisItem.isEmpty"));
      expect(produkScreenCode, contains('Pilih Komponen Paket (Produk Dijual)'));
    });

    test('Badge visual [PAKET] terpasang di baris tabel dan kartu produk', () {
      expect(produkScreenCode, contains("produk.jenisItem == 'PAKET'"));
      expect(produkScreenCode, contains("'PAKET'"));
    });

    test('AppSectionCard mengaitkan _tambahKomponenPaket saat jenis item PAKET', () {
      expect(produkScreenCode, contains("_jenisItem == 'PAKET'"));
      expect(produkScreenCode, contains("_tambahKomponenPaket"));
    });
  });
}
