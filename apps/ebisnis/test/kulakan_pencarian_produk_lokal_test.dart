import 'dart:io';

import 'package:ebisnis/services/pencarian_produk_lokal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final produk = <Map<String, Object?>>[
    {
      'id': 17,
      'kode': 'P-001',
      'barcode': '8998866201377',
      'nama': 'Produk Master Lama',
      'stok': 12,
      'harga_jual': 5000,
      'kategori_id': 3,
      'kategori_nama': 'Umum',
    },
  ];

  test('barcode fisik master lama cocok persis dari cache lokal', () {
    final cocok = produkCacheCocokPersis(produk, '8998866201377');
    expect(cocok?['id'], 17);
  });

  test('kode internal cocok tanpa peka kapital dan spasi', () {
    final cocok = produkCacheCocokPersis(produk, '  p-001  ');
    expect(cocok?['nama'], 'Produk Master Lama');
  });

  test('pencarian tidak memakai contains yang dapat memilih produk salah', () {
    expect(produkCacheCocokPersis(produk, '8998866'), isNull);
  });

  test('bentuk fallback kompatibel dengan respons scan Kulakan', () {
    final hasil = bentukProdukKulakanDariCache(produk.single);
    expect(hasil['produkId'], 17);
    expect(hasil['nama'], 'Produk Master Lama');
    expect(hasil['sumberCacheLokal'], isTrue);
    expect(hasil['faktorPembelianKeDasar'], 1);
  });

  test('pilihan Banbox selalu mengganti kode tampilan dengan nama master', () {
    final source =
        File('lib/screens/kulakan_bulk_entry_screen.dart').readAsStringSync();

    expect(source, contains('bool paksaIsiNamaMaster = false'));
    expect(
      source,
      contains('await _cariProduk(row, paksaIsiNamaMaster: true)'),
      reason: 'RawAutocomplete menulis kode ke controller setelah onSelected; '
          'jalur pilihan produk harus memaksa nama master diterapkan setelah '
          'verifikasi server maupun fallback cache lokal.',
    );
    expect(
      RegExp(r'paksaIsiNamaMaster \|\| row\.nama\.text\.trim\(\)\.isEmpty')
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(2),
      reason: 'Respons server dan fallback cache lokal harus memiliki kontrak '
          'pengisian nama yang sama.',
    );
  });
}
