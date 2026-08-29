import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/models.dart';

/// Kontrak Fase A (dok. 48/49): harga grosir per baris keranjang.
///
/// HANYA server yang menetapkan [ItemKeranjang.hargaGrosir] (peta `hargaGrosir`
/// pada respons `diskon_evaluasi`); klien tidak menghitung ambang sendiri.
/// Uji ini menjaga sisi klien dari kontrak itu: harga efektif dipakai subtotal,
/// dan hilangnya penetapan server mengembalikan harga katalog.
void main() {
  Produk produk({double harga = 1000}) => Produk(
        id: 1,
        kode: 'P1',
        barcode: '',
        nama: 'Produk Uji',
        hargaJual: harga,
        stok: 10,
        kategoriId: null,
        kategoriNama: '',
        gambarUrl: null,
      );

  test('tanpa penetapan server, harga efektif = harga katalog', () {
    final baris = ItemKeranjang(produk: produk(), jumlah: 3);
    expect(baris.hargaSatuanEfektif, 1000);
    expect(baris.subtotal, 3000);
  });

  test('hargaGrosir dari server menimpa harga katalog pada subtotal', () {
    final baris = ItemKeranjang(produk: produk(), jumlah: 60)..hargaGrosir = 880;
    expect(baris.hargaSatuanEfektif, 880);
    expect(baris.subtotal, 60 * 880);
  });

  test('penetapan dicabut (qty turun di bawah ambang) -> kembali ke katalog', () {
    final baris = ItemKeranjang(produk: produk(), jumlah: 60)..hargaGrosir = 880;
    // Peta hargaGrosir respons berikutnya tidak lagi memuat produk ini;
    // keranjang menyetel null -- harga katalog berlaku lagi, DUA ARAH.
    baris.hargaGrosir = null;
    expect(baris.hargaSatuanEfektif, 1000);
  });

  test('label kemasan: kelipatan bulat vs qty diubah kasir', () {
    final baris = ItemKeranjang(produk: produk(), jumlah: 100)
      ..kemasanNama = 'Karung 50kg'
      ..kemasanQtyDasar = 50;
    expect(baris.labelKemasan, '2 x Karung 50kg');
    // Kasir mengubah qty hingga tidak bulat: label tidak boleh berbohong
    // mengaku kelipatan -- jatuh ke bentuk informatif.
    baris.jumlah = 120;
    expect(baris.labelKemasan, 'Karung 50kg (isi 50)');
    // Tanpa snapshot kemasan, tidak ada label.
    expect(ItemKeranjang(produk: produk(), jumlah: 50).labelKemasan, isNull);
  });

  test('ekstra tetap dijumlah di atas harga efektif', () {
    final baris = ItemKeranjang(
      produk: produk(),
      jumlah: 2,
      ekstra: [ItemEkstra(id: 9, kode: 'E', nama: 'Topping', harga: 500)],
    )..hargaGrosir = 900;
    expect(baris.subtotal, (900 + 500) * 2);
  });
}
