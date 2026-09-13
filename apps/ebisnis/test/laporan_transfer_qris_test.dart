import 'dart:io';

import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('variasi Transfer, QRIS, dan QRS dikenali sebagai satu kanal', () {
    expect(metodeAdalahTransferAtauQris('Transfer'), isTrue);
    expect(metodeAdalahTransferAtauQris('QRIS BCA'), isTrue);
    expect(metodeAdalahTransferAtauQris('QRS - BSI'), isTrue);
    expect(metodeAdalahTransferAtauQris('QRIS Rp 20.000 + Tunai Rp 5.000'),
        isTrue);
    expect(metodeAdalahTransferAtauQris('Tunai'), isFalse);
    expect(metodeAdalahTransferAtauQris('Voucher Santri'), isFalse);
  });

  test('filter gabungan tidak memasukkan metode lain', () {
    final rows = <Map<String, dynamic>>[
      {'metode': 'Transfer', 'total': 10000},
      {'metode': 'QRS - BSI', 'total': 35000},
      {'metode': 'Tunai', 'total': 37000},
    ];
    final hasil =
        saringTransferDanQris(rows, bacaMetode: (row) => '${row['metode']}');
    expect(hasil.map((row) => row['total']), [10000, 35000]);
  });

  test('pilihan Transfer mengikuti QRS saat rentang tanggal berubah', () {
    expect(normalisasiFilterMetode('Transfer', ['QRS - BSI', 'Tunai']),
        metodeTransferQrisGabungan);
    expect(normalisasiFilterMetode('QRS - BSI', ['Transfer', 'Tunai']),
        metodeTransferQrisGabungan);
    expect(normalisasiFilterMetode('Tunai', ['QRS - BSI']), isEmpty);
  });

  test('ringkasan gabungan tetap menghitung nota dan nominal per kasir', () {
    final hasil = ringkasPenjualanPerKasir([
      {'kasir': 'Mutia', 'totalBiaya': 10000},
      {'kasir': 'Mutia', 'totalBiaya': 35000},
      {'kasir': 'Fikri', 'totalBiaya': 12000},
    ]);
    final mutia = hasil.singleWhere((row) => row['kasir'] == 'Mutia');
    final fikri = hasil.singleWhere((row) => row['kasir'] == 'Fikri');
    expect(mutia['jumlahTransaksi'], 2);
    expect(mutia['total'], 45000.0);
    expect(fikri['jumlahTransaksi'], 1);
    expect(fikri['total'], 12000.0);
  });

  test('opsi metode dimuat ulang setelah tanggal diterapkan', () {
    final source =
        File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync();
    expect(
        RegExp(r'await _muatOpsiMetode\(\);\s*await _muat\(\);')
            .allMatches(source)
            .length,
        greaterThanOrEqualTo(2));
  });
}
