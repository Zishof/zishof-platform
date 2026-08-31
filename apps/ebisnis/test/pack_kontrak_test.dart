import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/models.dart';

/// Kontrak PDF "settingan Pack" (31-08): produk ber-Pack dijual per pack
/// dengan harga TETAP (65.000/Dus, bukan 6 x 12.000). SERVER yang berwenang
/// menimpa harga saat bayar (terapkanSatuanJual); uji ini menjaga sisi klien:
/// pemetaan katalog, pratinjau harga pack, dan swa-batal pola Fase B.
void main() {
  Produk kecap({bool pack = true}) => Produk(
        id: 1,
        kode: 'KCP',
        barcode: '',
        nama: 'Kecap Manis 100g',
        hargaJual: 12000,
        stok: 500,
        kategoriId: null,
        kategoriNama: '',
        gambarUrl: null,
        satuanId: 7,
        satuanNama: 'Botol',
        packAktif: pack,
        satuanPackId: pack ? 8 : null,
        satuanPackNama: pack ? 'Dus' : '',
        hargaPack: pack ? 65000 : null,
        faktorPackKeDasar: pack ? 6 : null,
      );

  ItemKeranjang barisPack() => ItemKeranjang(produk: kecap(), jumlah: 6)
    ..satuanJualId = 8
    ..satuanJualNama = 'Dus'
    ..qtyInput = 1
    ..faktorKeDasar = 6
    ..hargaPackPerDasar = 65000 / 6;

  test('katalog lama tanpa field pack -> nonaktif', () {
    final j = {
      'id': 1,
      'kode': 'X',
      'barcode': '',
      'nama': 'X',
      'hargaJual': 1000,
      'stok': 1,
      'kategoriId': null,
      'kategoriNama': '',
      'gambarUrl': null,
    };
    final p = Produk.fromJson(j);
    expect(p.packAktif, isFalse);
    expect(p.hargaPack, isNull);
  });

  test('field pack katalog terbaca (skenario PDF: Dus isi 6, 65.000)', () {
    final j = {
      'id': 1,
      'kode': 'KCP',
      'barcode': '',
      'nama': 'Kecap',
      'hargaJual': 12000,
      'stok': 500,
      'kategoriId': null,
      'kategoriNama': '',
      'gambarUrl': null,
      'packAktif': true,
      'satuanPackId': 8,
      'satuanPackNama': 'Dus',
      'hargaPack': 65000,
      'faktorPackKeDasar': 6,
    };
    final p = Produk.fromJson(j);
    expect(p.packAktif, isTrue);
    expect(p.satuanPackNama, 'Dus');
    expect(p.hargaPack, 65000);
    expect(p.faktorPackKeDasar, 6);
  });

  test('pratinjau: 1 Dus -> subtotal persis Rp 65.000 (bukan 72.000)', () {
    final b = barisPack();
    expect(b.satuanJualKonsisten, isTrue);
    expect(b.subtotal, closeTo(65000, 0.000001));
    expect(b.labelSatuanJual, '1 Dus = 6 Botol');
  });

  test('swa-batal Fase B: qty diubah -> harga pack gugur ke katalog', () {
    final b = barisPack();
    b.jumlah = 7; // stepper +1 botol: bukan lagi 1 dus utuh
    expect(b.satuanJualKonsisten, isFalse);
    expect(b.hargaSatuanEfektif, 12000);
    expect(b.labelSatuanJual, isNull);
  });

  test('grosir dari server tetap menang atas harga pack', () {
    final b = barisPack()..hargaGrosir = 10000;
    expect(b.hargaSatuanEfektif, 10000);
  });
}
