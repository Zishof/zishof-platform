import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/models.dart';

void main() {
  Produk produk() => Produk(
        id: 1,
        kode: 'P1',
        barcode: '',
        nama: 'Produk Kanal',
        hargaJual: 10000,
        stok: 20,
        kategoriId: null,
        kategoriNama: '',
        gambarUrl: null,
      );

  test('harga kanal menimpa harga katalog', () {
    final item = ItemKeranjang(produk: produk(), jumlah: 2)
      ..hargaKanal = 12500;
    expect(item.hargaSatuanEfektif, 12500);
    expect(item.subtotal, 25000);
  });

  test('harga grosir tetap memiliki prioritas tertinggi', () {
    final item = ItemKeranjang(produk: produk(), jumlah: 50)
      ..hargaKanal = 12500
      ..hargaGrosir = 9000;
    expect(item.hargaSatuanEfektif, 9000);
  });

  test('kembali ke harga katalog saat kanal dilepas', () {
    final item = ItemKeranjang(produk: produk())..hargaKanal = 12500;
    item.hargaKanal = null;
    expect(item.hargaSatuanEfektif, 10000);
  });
}
