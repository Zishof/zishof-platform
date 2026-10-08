import 'package:ebisnis/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pesan penolakan bisnis dari respons API', () {
    test('alasan description dipakai ketika message hanya pesan payung', () {
      final pesan = ApiClient.pesanResponsGagal({
        'status': 'error',
        'kode': 'SERVER_ERROR',
        'message':
            'Server belum dapat menyelesaikan proses ini. Tidak ada perubahan parsial yang dipertahankan.',
        'description':
            'Saldo member tidak mencukupi. Saldo saat ini Rp300, transaksi ini memotong Rp164.500.',
      });

      expect(pesan, startsWith('Saldo member tidak mencukupi.'));
    });

    test('pesan spesifik tetap menang atas description', () {
      final pesan = ApiClient.pesanResponsGagal({
        'message': 'Produk sedang tidak tersedia.',
        'description': 'Rincian internal lain.',
      });

      expect(pesan, 'Produk sedang tidak tersedia.');
    });

    test('description menjadi fallback jika message kosong', () {
      expect(
        ApiClient.pesanResponsGagal({'message': '', 'description': 'Ditolak.'}),
        'Ditolak.',
      );
    });

    test('respons kosong memakai kalimat aman', () {
      expect(ApiClient.pesanResponsGagal({}), 'Permintaan belum berhasil.');
    });
  });
}
