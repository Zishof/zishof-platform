import 'package:ebisnis/screens/produk_stok_tanggal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ringkasan menjumlahkan nilai server untuk produk yang tampil', () {
    const hasil = HasilStokTanggal(
      kolom: ['Kode', 'Nama Produk', 'Nilai Stok'],
      baris: [
        [101, 'Produk A', 24333.44],
        [102, 'Produk B', '24.712,89'],
      ],
      stokPerKode: {},
    );

    expect(hasil.jumlahProduk, 2);
    expect(hasil.totalNilaiPersediaan, closeTo(49046.33, 0.001));
  });

  test('tidak mengarang total jika kolom nilai tidak ada atau tidak terbaca',
      () {
    const tanpaKolom = HasilStokTanggal(
      kolom: ['Kode', 'Nama Produk'],
      baris: [
        [101, 'Produk A']
      ],
      stokPerKode: {},
    );
    const nilaiTidakValid = HasilStokTanggal(
      kolom: ['Nilai Persediaan'],
      baris: [
        ['tidak diketahui']
      ],
      stokPerKode: {},
    );

    expect(tanpaKolom.totalNilaiPersediaan, isNull);
    expect(nilaiTidakValid.totalNilaiPersediaan, isNull);
  });

  test('harga jual tidak dipakai sebagai pengganti HPP untuk nilai stok', () {
    const tanpaHpp = HasilStokTanggal(
      kolom: ['Kode', 'Nama Produk', 'Stok', 'Harga Jual'],
      baris: [
        [101, 'Produk A', 4, 20000],
      ],
      stokPerKode: {},
    );

    expect(tanpaHpp.totalNilaiPersediaan, isNull);
  });

  test('nilai stok memakai HPP resmi dari laporan atau cache', () {
    const dariLaporan = HasilStokTanggal(
      kolom: ['Kode', 'Nama Produk', 'Stok', 'Harga Beli'],
      baris: [
        [101, 'Produk A', 4, 12500],
      ],
      stokPerKode: {},
    );
    const dariCache = HasilStokTanggal(
      kolom: ['Kode', 'Nama Produk', 'Stok'],
      baris: [
        [101, 'Produk A', 4],
      ],
      stokPerKode: {},
      hargaBeliPerKode: {'101': 12500},
    );

    expect(dariLaporan.totalNilaiPersediaan, 50000);
    expect(dariCache.totalNilaiPersediaan, 50000);
  });
}
