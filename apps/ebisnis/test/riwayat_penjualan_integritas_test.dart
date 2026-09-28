import 'package:ebisnis/screens/riwayat_penjualan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalisasi barcode struk', () {
    test('menerima kode transaksi mentah', () {
      expect(normalisasiKodeTransaksiDariScan('  AB260830ABC123  '),
          'AB260830ABC123');
    });

    test('mengambil nomor nota dari JSON dan URL', () {
      expect(
        normalisasiKodeTransaksiDariScan('{"nomorNota":"EB260830000123"}'),
        'EB260830000123',
      );
      expect(
        normalisasiKodeTransaksiDariScan(
            'https://pos.example/struk?kodeTransaksi=AB260830XYZ987'),
        'AB260830XYZ987',
      );
    });
  });

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

  group('visibilitas arsip lokal tertahan', () {
    test('transaksi pending dan gagal tetap tampil walau di luar tanggal aktif',
        () {
      final hariLama = DateTime(2026, 9, 25, 20, 54, 54);
      final hariIni = DateTime(2026, 9, 28);

      expect(
        tanggalArsipLokalMasukRiwayat(
          hariLama,
          status: 'GAGAL',
          mulai: hariIni,
          sampai: hariIni,
        ),
        isTrue,
      );
      expect(
        tanggalArsipLokalMasukRiwayat(
          hariLama,
          status: 'PENDING',
          mulai: hariIni,
          sampai: hariIni,
        ),
        isTrue,
      );
    });

    test('transaksi lokal selesai tetap mengikuti filter tanggal', () {
      expect(
        tanggalArsipLokalMasukRiwayat(
          DateTime(2026, 9, 25),
          status: 'SYNCED',
          mulai: DateTime(2026, 9, 28),
          sampai: DateTime(2026, 9, 28),
        ),
        isFalse,
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
