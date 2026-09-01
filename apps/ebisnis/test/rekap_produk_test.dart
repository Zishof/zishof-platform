import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/screens/laporan_transaksi_screen.dart';

/// Rekap per produk dirangkum dari baris rincian yang sama, sehingga angkanya
/// tidak pernah berselisih dengan mode rincian pada filter yang sama.
void main() {
  List<Map<String, dynamic>> baris() => [
        {
          'idTransaksi': 1,
          'nomorNota': 'Order 001 - 0000 - 001',
          'produkKode': 'A',
          'produkNama': 'Kopi Sachet',
          'satuan': 'Pcs',
          'qty': 12,
          'total': 24000,
        },
        {
          'idTransaksi': 1,
          'nomorNota': 'Order 001 - 0000 - 001',
          'produkKode': 'A',
          'produkNama': 'Kopi Sachet',
          'satuan': 'Pcs',
          'qty': 1,
          'total': 1500,
        },
        {
          'idTransaksi': 2,
          'nomorNota': 'Order 001 - 0000 - 002',
          'produkKode': 'B',
          'produkNama': 'Roti Manis',
          'satuan': 'Pcs',
          'qty': 3,
          'total': 9000,
        },
      ];

  test('baris produk sama dijumlahkan', () {
    final rekap = rekapProdukDariRincian(baris());
    final kopi = rekap.firstWhere((r) => r['produkKode'] == 'A');
    expect(kopi['qty'], 13);
    expect(kopi['total'], 25500);
  });

  test('satu nota dengan produk sama dua baris tetap satu transaksi', () {
    final rekap = rekapProdukDariRincian(baris());
    final kopi = rekap.firstWhere((r) => r['produkKode'] == 'A');
    expect(kopi['jumlahTransaksi'], 1);
  });

  test('produk berbeda tidak tercampur', () {
    final rekap = rekapProdukDariRincian(baris());
    expect(rekap.length, 2);
    final roti = rekap.firstWhere((r) => r['produkKode'] == 'B');
    expect(roti['qty'], 3);
    expect(roti['jumlahTransaksi'], 1);
  });

  test('urut menurun berdasarkan nilai penjualan', () {
    final rekap = rekapProdukDariRincian(baris());
    expect(rekap.first['produkKode'], 'A');
  });

  test('total rekap sama dengan total baris rincian', () {
    final rekap = rekapProdukDariRincian(baris());
    final totalRekap =
        rekap.fold<double>(0, (j, r) => j + (r['total'] as double));
    final totalBaris = baris()
        .fold<double>(0, (j, b) => j + ((b['total'] as num).toDouble()));
    expect(totalRekap, totalBaris);
  });

  test('produk tanpa kode dikelompokkan memakai namanya', () {
    final rekap = rekapProdukDariRincian([
      {'idTransaksi': 9, 'produkKode': '', 'produkNama': 'Produk Dihapus', 'qty': 2, 'total': 8000},
      {'idTransaksi': 10, 'produkKode': '', 'produkNama': 'produk dihapus', 'qty': 1, 'total': 4000},
    ]);
    expect(rekap.length, 1);
    expect(rekap.first['qty'], 3);
    expect(rekap.first['jumlahTransaksi'], 2);
  });

  test('daftar kosong menghasilkan rekap kosong, bukan galat', () {
    expect(rekapProdukDariRincian(const []), isEmpty);
  });
}
