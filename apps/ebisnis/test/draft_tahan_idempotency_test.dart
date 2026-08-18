import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

Produk produk(int id, String kode, double harga) => Produk(
      id: id,
      kode: kode,
      barcode: kode,
      nama: 'Produk $kode',
      hargaJual: harga,
      stok: 100,
      kategoriId: 1,
      kategoriNama: 'Umum',
      gambarUrl: null,
    );

void main() {
  test('tahan ulang membuang salinan rincian identik tanpa menggandakan qty',
      () {
    final pertama = ItemKeranjang(produk: produk(1, 'A', 110100));
    final kedua = ItemKeranjang(produk: produk(2, 'B', 198000));
    final salinanPertama = ItemKeranjang(produk: produk(1, 'A', 110100));
    final salinanKedua = ItemKeranjang(produk: produk(2, 'B', 198000));

    final hasil = normalisasiDuplikatKeranjangTertahan(
        [pertama, kedua, salinanPertama, salinanKedua]);

    expect(hasil, hasLength(2));
    expect(hasil.map((e) => e.produk.kode), ['A', 'B']);
    expect(hasil.fold<double>(0, (sum, e) => sum + e.subtotal), 308100);
    expect(hasil.first.jumlah, 1);
  });

  test('baris berbeda qty promo atau ekstra tidak dianggap duplikat', () {
    final dasar = produk(1, 'A', 10000);
    final qtyDua = ItemKeranjang(produk: dasar, jumlah: 2);
    final promo = ItemKeranjang(produk: dasar, jumlah: 1, diskon: 1000);
    final ekstra = ItemKeranjang(
      produk: dasar,
      jumlah: 1,
      ekstra: const [ItemEkstra(id: 9, kode: 'E', nama: 'Ekstra', harga: 2000)],
    );

    final hasil = normalisasiDuplikatKeranjangTertahan(
        [ItemKeranjang(produk: dasar), qtyDua, promo, ekstra]);

    expect(hasil, hasLength(4));
  });
}
