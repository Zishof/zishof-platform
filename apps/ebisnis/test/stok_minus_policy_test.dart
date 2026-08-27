import 'package:ebisnis/models.dart';
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Produk _produk({required int stok, bool izinProduk = false}) => Produk(
      id: 1,
      kode: 'P-001',
      barcode: '8990001',
      nama: 'Produk Uji',
      hargaJual: 10000,
      stok: stok,
      kategoriId: null,
      kategoriNama: 'Umum',
      gambarUrl: null,
      izinkanJualMinusStok: izinProduk,
    );

void main() {
  test('stok tersedia selalu boleh dijual', () {
    expect(
      produkBolehDijualMenurutStok(
        _produk(stok: 1),
        paksaStokMinusToko: false,
      ),
      isTrue,
    );
  });

  test('override toko membuka produk stok nol dan minus', () {
    for (final stok in <int>[0, -1]) {
      expect(
        produkBolehDijualMenurutStok(
          _produk(stok: stok),
          paksaStokMinusToko: true,
        ),
        isTrue,
      );
    }
  });

  test('izin per-produk membuka stok nol saat override toko mati', () {
    expect(
      produkBolehDijualMenurutStok(
        _produk(stok: 0, izinProduk: true),
        paksaStokMinusToko: false,
      ),
      isTrue,
    );
  });

  test('stok nol tetap diblokir bila kedua izin mati', () {
    expect(
      produkBolehDijualMenurutStok(
        _produk(stok: 0),
        paksaStokMinusToko: false,
      ),
      isFalse,
    );
  });

  test('izin per-produk ikut dipersistenkan ke cache lokal', () {
    final row = Produk.baseKeCacheRow(<String, dynamic>{
      'id': 1,
      'kode': 'P-001',
      'nama': 'Produk Uji',
      'izinkanJualMinusStok': true,
    });
    expect(row['izinkan_jual_minus_stok'], 1);
  });
}
