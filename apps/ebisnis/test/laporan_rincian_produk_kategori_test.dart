import 'dart:io';

import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Kategori pada Laporan Transaksi - Rincian Produk', () {
    test('labelKategoriRincian tidak pernah menghasilkan sel kosong (blank)',
        () {
      expect(labelKategoriRincian(null), '-');
      expect(labelKategoriRincian(''), '-');
      expect(labelKategoriRincian('   '), '-');
      expect(labelKategoriRincian(' KANTIN '), 'KANTIN');
      expect(labelKategoriRincian('Minuman'), 'Minuman');
    });

    test(
        'bangunIndeksKategoriDariProdukCache & perkayaKategoriBarisRincian '
        'memulihkan kategori dari id, kode kanonis EB...-AN..., dan nama', () {
      final indeks = bangunIndeksKategoriDariProdukCache([
        {
          'id': 888,
          'kode': 'AN000888',
          'nama': 'Dimsum goreng',
          'kategori_nama': 'KANTIN',
          'detail_json': null,
        },
        {
          'id': 247,
          'kode': 'AN000247',
          'nama': 'LE MINERAL 1,5 ML BESAR',
          'kategori_nama': '',
          'detail_json': '{"jenisProdukNama":"Minuman"}',
        },
        {
          'id': 510,
          'kode': 'AN000510',
          'nama': 'BUKU TULIS SIDU CAMPUS',
          'kategori_nama': 'ATK',
          'detail_json': null,
        },
      ]);

      expect(indeks.daftarKategori, ['ATK', 'KANTIN', 'Minuman']);

      // 1. Cocok lewat kode kanonis ketika snapshot transaksi berawalan EB...
      final barisDimsum = perkayaKategoriBarisRincian({
        'produkKode': 'EB261112091500ABCD-AN000888',
        'produkNama': 'Dimsum goreng',
        'qty': 2,
        'hargaSatuan': 6000,
        'total': 12000,
      }, indeks.peta);
      expect(barisDimsum['kategori'], 'KANTIN');
      expect(barisDimsum['kategoriTampil'], 'KANTIN');

      // 2. Cocok lewat produkId
      final barisMineral = perkayaKategoriBarisRincian({
        'produkId': 247,
        'produkKode': '',
        'produkNama': 'LE MINERAL 1,5 ML BESAR',
        'qty': 1,
        'hargaSatuan': 6000,
        'total': 6000,
      }, indeks.peta);
      expect(barisMineral['kategori'], 'Minuman');
      expect(barisMineral['kategoriTampil'], 'Minuman');

      // 3. Produk tanpa kategori menampilkan '-' untuk tampilan tetapi menyimpan '' untuk filter Tanpa kategori
      final barisTanpa = perkayaKategoriBarisRincian({
        'produkId': 999999,
        'produkKode': 'XX999',
        'produkNama': 'Barang Lepas',
        'qty': 1,
        'hargaSatuan': 5000,
        'total': 5000,
      }, indeks.peta);
      expect(barisTanpa['kategori'], '');
      expect(barisTanpa['kategoriTampil'], '-');
    });

    test(
        'cocokFilterKategoriRincian menyaring Semua kategori, nama kategori '
        '(case-insensitive), dan Tanpa kategori tanpa membocorkan item nota lain',
        () {
      final kantin = {'produkNama': 'MUMUBE', 'kategori': 'KANTIN'};
      final makanan = {'produkNama': 'Risol Hani', 'kategori': 'MAKANAN'};
      final kosong = {'produkNama': 'Item Lama', 'kategori': ''};

      expect(cocokFilterKategoriRincian(kantin, ''), isTrue);
      expect(cocokFilterKategoriRincian(makanan, ''), isTrue);
      expect(cocokFilterKategoriRincian(kosong, ''), isTrue);

      expect(cocokFilterKategoriRincian(kantin, 'kantin'), isTrue);
      expect(cocokFilterKategoriRincian(makanan, 'kantin'), isFalse);
      expect(cocokFilterKategoriRincian(kosong, 'kantin'), isFalse);

      expect(
        cocokFilterKategoriRincian(kosong, kTokenTanpaKategoriRincian),
        isTrue,
      );
      expect(
        cocokFilterKategoriRincian(kantin, kTokenTanpaKategoriRincian),
        isFalse,
      );
    });

    test(
        'rekapProdukDariRincian mempertahankan kategori dan menyertakan kategoriTampil',
        () {
      final rekap = rekapProdukDariRincian([
        {
          'idTransaksi': 1,
          'produkKode': 'AN000888',
          'produkNama': 'Dimsum goreng',
          'kategori': '',
          'satuan': 'Pcs',
          'qty': 2,
          'hargaSatuan': 6000,
          'total': 12000,
        },
        {
          'idTransaksi': 2,
          'produkKode': 'AN000888',
          'produkNama': 'Dimsum goreng',
          'kategori': 'KANTIN',
          'satuan': 'Pcs',
          'qty': 3,
          'hargaSatuan': 6000,
          'total': 18000,
        },
        {
          'idTransaksi': 2,
          'produkKode': 'AN009999',
          'produkNama': 'Produk Belum Berkategori',
          'kategori': '',
          'satuan': 'Pcs',
          'qty': 1,
          'hargaSatuan': 5000,
          'total': 5000,
        },
      ]);

      expect(rekap, hasLength(2));
      expect(rekap[0]['produkKode'], 'AN000888');
      expect(rekap[0]['kategori'], 'KANTIN');
      expect(rekap[0]['kategoriTampil'], 'KANTIN');
      expect(rekap[0]['qty'], 5.0);
      expect(rekap[0]['total'], 30000.0);

      expect(rekap[1]['produkKode'], 'AN009999');
      expect(rekap[1]['kategori'], '');
      expect(rekap[1]['kategoriTampil'], '-');
    });

    test(
        'kontrak UI _TabRincianProdukState & LaporanDetailScreen menyediakan '
        'dropdown Kategori Produk dan meneruskan filter ke server & ekspor',
        () {
      final source =
          File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync();
      final awal = source.indexOf('class _TabRincianProdukState');
      expect(awal, greaterThanOrEqualTo(0));
      final akhir = source.indexOf('Widget build(BuildContext context)', awal);
      expect(akhir, greaterThan(awal));

      final state = source.substring(awal, akhir);
      expect(
        state,
        contains("if (_kategori.trim().isNotEmpty) 'kategori': _kategori.trim()"),
      );
      expect(
        state,
        contains("DynamicReportColumn('kategoriTampil', 'Kategori')"),
      );

      final ui = source.substring(
        akhir,
        source.indexOf(
            '_AnalitikLaporanFooter(statistik: widget.statistik)', akhir),
      );
      expect(ui, contains("labelText: 'Kategori Produk'"));
      expect(ui, contains("Text('Semua kategori'"));
      expect(ui, contains("Text('Tanpa kategori'"));

      final detailSource =
          File('lib/screens/laporan_detail_screen.dart').readAsStringSync();
      expect(
        detailSource,
        contains("widget.item['kategoriProduk'] == true"),
      );
      expect(
        detailSource,
        contains("'jenisProdukId': '\$_jenisProdukId'"),
      );
    });
  });
}
