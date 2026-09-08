import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/screens/laporan_transaksi_screen.dart';

void main() {
  test('baris Excel Tunai memakai nominal tunai pada nota split', () {
    final row = barisEksporRincianPenerimaan(
      {
        'tanggal': '2026-09-08',
        'kasir': 'Mutia',
        'metode': 'Tunai',
      },
      {
        'waktu': '2026-09-08 16:30:53',
        'nomorNota': 'Order 001 - 0001 - 021',
        'pembeli': 'Umum',
        'metode': 'QRIS Rp 20.000 + Tunai Rp 15.000',
        'qty': 2,
        'totalBiaya': 35000,
        'bayarTunai': 15000,
      },
    );

    expect(row['tanggal'], '2026-09-08');
    expect(row['kasir'], 'Mutia');
    expect(row['metodeTampil'], 'Tunai');
    expect(row['totalNota'], 35000);
    expect(row['penerimaanMetode'], 15000);
  });

  test('nota tunai lama tanpa snapshot memakai total nota', () {
    final row = barisEksporRincianPenerimaan(
      {'tanggal': '2026-09-08', 'kasir': 'Mutia', 'metode': 'Tunai'},
      {
        'waktu': '2026-09-08 16:30:53',
        'nomorNota': 'Order 001 - 0001 - 022',
        'totalBiaya': 11000,
        'bayarTunai': 0,
      },
    );

    expect(row['totalNota'], 11000);
    expect(row['penerimaanMetode'], 11000);
  });

  test('metode non-tunai pada nota split memakai porsi metode', () {
    final row = barisEksporRincianPenerimaan(
      {'tanggal': '2026-09-08', 'kasir': 'Mutia', 'metode': 'QRIS BSI'},
      {
        'waktu': '2026-09-08 16:30:53',
        'nomorNota': 'Order 001 - 0001 - 023',
        'totalBiaya': 43000,
        'metode': 'QRIS BSI Rp 30.000 + Tunai Rp 13.000',
        'bayarTunai': 13000,
      },
    );

    expect(row['metodeTampil'], 'QRIS BSI');
    expect(row['totalNota'], 43000);
    expect(row['penerimaanMetode'], 30000);
  });

  test('metode tunggal tetap menampilkan total nota', () {
    final row = barisEksporRincianPenerimaan(
      {'tanggal': '2026-09-08', 'kasir': 'Mutia', 'metode': 'Transfer'},
      {
        'waktu': '2026-09-08 16:30:53',
        'nomorNota': 'Order 001 - 0001 - 024',
        'totalBiaya': 43000,
        'metode': 'Transfer',
      },
    );

    expect(row['penerimaanMetode'], 43000);
  });
}
