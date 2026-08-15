import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

Produk produk(int id, String nama) => Produk(
      id: id,
      kode: 'K$id',
      barcode: 'B$id',
      nama: nama,
      hargaJual: 1000,
      stok: 10,
      kategoriId: null,
      kategoriNama: '',
      gambarUrl: null,
    );

void main() {
  test('item yang baru dipindai ditempatkan paling atas tanpa kehilangan qty',
      () {
    final lama = ItemKeranjang(produk: produk(1, 'Barang Lama'), jumlah: 3);
    final terbaru = ItemKeranjang(produk: produk(2, 'Barang Terbaru'));
    final keranjang = <ItemKeranjang>[lama, terbaru];

    terbaru.jumlah++;
    tempatkanItemKeranjangTerbaruDiDepan(keranjang, terbaru);

    expect(keranjang.first, same(terbaru));
    expect(keranjang.first.jumlah, 2);
    expect(keranjang.last, same(lama));
    expect(keranjang.last.jumlah, 3);
  });
}
