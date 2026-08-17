import 'package:ebisnis/screens/riwayat_penjualan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('filter integritas riwayat penjualan', () {
    test('tidak memasukkan arsip lokal yang belum diaudit server', () {
      final hasil = saringArsipLokalUntukFilterIntegritas([
        {
          'nomorNota': 'AB21708202600075',
          'totalBiaya': 300000,
          'statusSinkronLokal': 'SYNCED',
        }
      ], hanyaTransaksiTidakValid: true);

      expect(hasil, isEmpty);
    });

    test('tetap memasukkan hasil audit eksplisit yang benar-benar tidak valid',
        () {
      final row = {
        'nomorNota': 'TRX-SELISIH',
        'totalMaster': 300000,
        'totalDetail': 299000,
        'transaksiTidakValid': true,
      };

      final hasil = saringArsipLokalUntukFilterIntegritas(
        [row],
        hanyaTransaksiTidakValid: true,
      );

      expect(hasil, [row]);
    });

    test('tidak mengubah arsip ketika filter integritas nonaktif', () {
      final rows = [
        {'nomorNota': 'VALID-1'},
        {'nomorNota': 'VALID-2'},
      ];

      expect(
        saringArsipLokalUntukFilterIntegritas(
          rows,
          hanyaTransaksiTidakValid: false,
        ),
        same(rows),
      );
    });
  });
}
