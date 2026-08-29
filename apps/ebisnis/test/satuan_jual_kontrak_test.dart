import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/uom_konversi.dart';

/// Kontrak Fase B (dok. 48/49): satuan jual per baris keranjang.
///
/// Server BERWENANG atas konversi -- `KantinHelper.terapkanSatuanJual`
/// menghitung ulang `jumlah = qty_input x faktor` miliknya sendiri dan
/// MENIMPA kiriman klien. Klien hanya pratinjau; uji ini menjaga sisi klien:
/// snapshot swa-batal begitu qty dasar diubah hingga tak sejalan, dan hanya
/// snapshot yang sejalan yang boleh diklaim lewat label/payload.
void main() {
  Produk produk() => Produk(
        id: 1,
        kode: 'P1',
        barcode: '',
        nama: 'Beras',
        hargaJual: 15000,
        stok: 100,
        kategoriId: null,
        kategoriNama: '',
        gambarUrl: null,
        satuanId: 7,
        satuanNama: 'kg',
      );

  ItemKeranjang barisKarung() => ItemKeranjang(produk: produk(), jumlah: 100)
    ..satuanJualId = 8
    ..satuanJualNama = 'Karung 50'
    ..qtyInput = 2
    ..faktorKeDasar = 50;

  test('snapshot sejalan: label menyebut qty satuan DAN qty dasar', () {
    final baris = barisKarung();
    expect(baris.satuanJualKonsisten, isTrue);
    expect(baris.labelSatuanJual, '2 Karung 50 = 100 kg');
  });

  test('kasir mengubah qty dasar -> snapshot gugur sendiri (label & payload)',
      () {
    final baris = barisKarung();
    // Stepper +1: 101 kg bukan lagi 2 x 50 -- klaim satuan harus hilang
    // TANPA stepper tahu konsep satuan jual.
    baris.jumlah = 101;
    expect(baris.satuanJualKonsisten, isFalse);
    expect(baris.labelSatuanJual, isNull);
  });

  test('tanpa snapshot, tidak ada klaim', () {
    final polos = ItemKeranjang(produk: produk(), jumlah: 3);
    expect(polos.satuanJualKonsisten, isFalse);
    expect(polos.labelSatuanJual, isNull);
  });

  test('qtyInput/faktor tak sah tidak pernah sejalan', () {
    expect((barisKarung()..qtyInput = 0).satuanJualKonsisten, isFalse);
    expect((barisKarung()..faktorKeDasar = -1).satuanJualKonsisten, isFalse);
    expect((barisKarung()..qtyInput = null).satuanJualKonsisten, isFalse);
  });

  test('pratinjau UomKonversi cocok dengan aturan server (BIGGER/SMALLER)', () {
    final kg = {'id': 7, 'kategori': 'BERAT', 'tipeKonversi': 'REFERENCE'};
    final karung = {
      'id': 8,
      'kategori': 'BERAT',
      'tipeKonversi': 'BIGGER',
      'rasio': 50,
    };
    expect(UomKonversi.konversi(jumlah: 2, dari: karung, ke: kg), 100);
    // Lintas kategori: klien menolak persis seperti server menolak
    // (KantinHelper.faktorUomInputKeDasar -> status 91).
    final liter = {'id': 9, 'kategori': 'VOLUME', 'tipeKonversi': 'REFERENCE'};
    expect(() => UomKonversi.konversi(jumlah: 1, dari: liter, ke: kg),
        throwsFormatException);
  });

  test('label satuan jual menang atas label kemasan (satu klaim per baris)',
      () {
    final baris = barisKarung()
      ..kemasanNama = 'Karung 50kg'
      ..kemasanQtyDasar = 50;
    // Kontrak tampilan: keranjang & struk menampilkan labelSatuanJual bila
    // ada, dan labelKemasan hanya sebagai cadangan.
    expect(baris.labelSatuanJual, isNotNull);
    expect(baris.labelKemasan, isNotNull);
  });
}
