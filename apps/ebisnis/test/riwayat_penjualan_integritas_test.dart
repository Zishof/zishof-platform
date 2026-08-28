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

  group('penggabungan transaksi server dan lokal', () {
    test('menggabungkan kode stabil yang sama dan mempertahankan id server',
        () {
      final hasil = gabungkanTransaksiServerDanLokal(
        [
          {
            'idTransaksi': 123,
            'kodeUnik': 'EB260828153412422S',
            'nomorNota': 'Order 001 - 0001 - 001 (EB260828153412422S)',
            'totalBiaya': 13500,
          },
        ],
        [
          {
            'nomorNota': 'EB260828153412422S',
            'statusSinkronLokal': 'SYNCED',
            'payloadLokal': {
              'kodeUnik': 'EB260828153412422S',
              'transaksi': <Object?>[],
            },
          },
        ],
        batas: 15,
      );

      expect(hasil, hasLength(1));
      expect(hasil.single['idTransaksi'], 123);
      expect(
        hasil.single['nomorNota'],
        'Order 001 - 0001 - 001 (EB260828153412422S)',
      );
      expect(hasil.single['statusSinkronLokal'], 'SYNCED');
      expect(hasil.single['payloadLokal'], isA<Map>());
    });

    test('mempertahankan transaksi lokal yang belum ada di server', () {
      final hasil = gabungkanTransaksiServerDanLokal(
        [
          {
            'idTransaksi': 456,
            'kodeUnik': 'SERVER-ONLY',
            'nomorNota': 'Order Server (SERVER-ONLY)',
          },
        ],
        [
          {
            'nomorNota': 'LOCAL-PENDING',
            'statusSinkronLokal': 'PENDING',
            'payloadLokal': {
              'kodeUnik': 'LOCAL-PENDING',
              'transaksi': <Object?>[],
            },
          },
        ],
        batas: 15,
      );

      expect(hasil, hasLength(2));
      expect(hasil.first['nomorNota'], 'LOCAL-PENDING');
      expect(hasil.last['idTransaksi'], 456);
    });
  });
}
