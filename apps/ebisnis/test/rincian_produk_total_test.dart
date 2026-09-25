import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';

void main() {
  group('hitungTotalBarisRincian', () {
    test(
        'mengoreksi baris anomali DB di mana total == hargaSatuan padahal qty > 1',
        () {
      // Kasus live Al-Bahjah An-Nahl (Nipis Madu 330ml): Qty 2, Harga 5.000, Total 5.000
      final barisAnomali = {
        'produkKode': 'AN000259',
        'produkNama': 'NIPIS MADU 330ML',
        'qty': 2.0,
        'hargaSatuan': 5000.0,
        'diskon': 0.0,
        'total': 5000.0,
      };

      final total = hitungTotalBarisRincian(barisAnomali);
      expect(total, 10000.0);
    });

    test('mengoreksi baris dengan total 0 atau null', () {
      final barisNol = {
        'produkKode': 'AN000649',
        'produkNama': 'AICE CHOCO MALT',
        'qty': 5.0,
        'hargaSatuan': 2000.0,
        'diskon': 0.0,
        'total': 0.0,
      };

      final total = hitungTotalBarisRincian(barisNol);
      expect(total, 10000.0);
    });

    test('mempertahankan total normal yang sudah benar', () {
      final barisNormal = {
        'produkKode': 'AN000853',
        'produkNama': 'AICE COFFEE CRISPY',
        'qty': 1.0,
        'hargaSatuan': 5000.0,
        'diskon': 0.0,
        'total': 5000.0,
      };

      final total = hitungTotalBarisRincian(barisNormal);
      expect(total, 5000.0);
    });

    test('memperhitungkan diskon pada koreksi baris', () {
      final barisDiskon = {
        'produkKode': 'ROTI01',
        'produkNama': 'Roti Bakar',
        'qty': 4.0,
        'hargaSatuan': 7000.0,
        'diskon': 4000.0,
        'total': 7000.0, // anomali: tersimpan seharga satuan
      };

      final total = hitungTotalBarisRincian(barisDiskon);
      // 4 * 7000 - 4000 = 24000
      expect(total, 24000.0);
    });
  });

  group('rekapProdukDariRincian dengan baris anomali', () {
    test(
        'rekap mengalikan qty x harga saat baris tersimpan total = hargaSatuan',
        () {
      final baris = [
        {
          'produkKode': 'AN000259',
          'produkNama': 'NIPIS MADU 330ML',
          'qty': 2.0,
          'hargaSatuan': 5000.0,
          'diskon': 0.0,
          'total': 5000.0,
          'nomorNota': 'POS-001',
        },
        {
          'produkKode': 'AN000259',
          'produkNama': 'NIPIS MADU 330ML',
          'qty': 1.0,
          'hargaSatuan': 5000.0,
          'diskon': 0.0,
          'total': 5000.0,
          'nomorNota': 'POS-002',
        },
      ];

      final rekap = rekapProdukDariRincian(baris);
      expect(rekap.length, 1);
      expect(rekap.first['qty'], 3.0);
      // 2 * 5000 + 1 * 5000 = 15000
      expect(rekap.first['total'], 15000.0);
    });
  });
}
