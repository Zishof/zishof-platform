import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/services/peringatan_transaksi.dart';

/// Saluran tunggal peringatan pasca-transaksi (docs/pos/80).
///
/// Enam peringatan berbentuk sama -- "transaksi diterima, ada yang perlu
/// direkonsiliasi" -- dahulu berupa enam field lepas, dan LIMA di antaranya tidak
/// pernah dibaca kanal mana pun (docs/pos/79). Sebabnya struktural: tiap field
/// baru menuntut empat titik di aplikasi ini disentuh.
///
/// Kelas ini satu-satunya tempat saluran itu dibaca, jadi di sinilah cadangan
/// versi lama dan bentuk-bentuk yang mungkin datang dari server harus dikunci.
void main() {
  group('membaca saluran baru', () {
    test('daftar {kode, pesan} diratakan jadi kalimat', () {
      final hasil = PeringatanTransaksi.dari({
        'peringatanTransaksi': [
          {'kode': 'STOK_KURANG', 'pesan': 'Saldo stok Nasi Koloke tidak mencukupi.'},
          {'kode': 'SESI_KAS_SUDAH_TUTUP', 'pesan': 'Sesi kas SK-01 sudah ditutup.'},
        ],
      });
      expect(hasil, [
        'Saldo stok Nasi Koloke tidak mencukupi.',
        'Sesi kas SK-01 sudah ditutup.',
      ]);
    });

    test('lebih dari satu peringatan tidak saling menimpa', () {
      // Inilah yang tidak mungkin dilakukan bentuk lama: satu field per jenis
      // berarti dua peringatan berbeda tidak pernah dapat tampil bersama.
      final hasil = PeringatanTransaksi.dari({
        'peringatanTransaksi': [
          {'kode': 'A', 'pesan': 'satu'},
          {'kode': 'B', 'pesan': 'dua'},
          {'kode': 'C', 'pesan': 'tiga'},
        ],
      });
      expect(hasil.length, 3);
      expect(PeringatanTransaksi.gabung({
        'peringatanTransaksi': [
          {'kode': 'A', 'pesan': 'satu'},
          {'kode': 'B', 'pesan': 'dua'},
        ],
      }), 'satu dua');
    });

    test('entri kosong dibuang, bukan ditampilkan sebagai baris hampa', () {
      final hasil = PeringatanTransaksi.dari({
        'peringatanTransaksi': [
          {'kode': 'A', 'pesan': '   '},
          {'kode': 'B'},
          {'kode': 'C', 'pesan': 'nyata'},
        ],
      });
      expect(hasil, ['nyata']);
    });

    test('daftar berisi string polos juga diterima', () {
      // Menolak bentuk ini hanya akan membuang peringatan yang sah bila suatu
      // saat ada peladen yang mengirimkannya begitu.
      expect(PeringatanTransaksi.dari({'peringatanTransaksi': ['halo']}), ['halo']);
    });
  });

  group('cadangan untuk peladen versi lama', () {
    test('peringatanStok dibaca bila saluran belum ada', () {
      expect(PeringatanTransaksi.dari({'peringatanStok': 'stok kurang'}),
          ['stok kurang']);
    });

    test('saluran baru MENANG atas field lama bila keduanya ada', () {
      // Server mengirim keduanya untuk sementara (field lama dipertahankan demi
      // aplikasi yang belum diperbarui). Membaca dua-duanya akan menampilkan
      // peringatan stok DUA KALI.
      final hasil = PeringatanTransaksi.dari({
        'peringatanTransaksi': [
          {'kode': 'STOK_KURANG', 'pesan': 'stok kurang'},
        ],
        'peringatanStok': 'stok kurang',
      });
      expect(hasil, ['stok kurang'], reason: 'tidak boleh ganda');
    });

    test('saluran kosong jatuh ke field lama, bukan menghasilkan kosong', () {
      final hasil = PeringatanTransaksi.dari({
        'peringatanTransaksi': const [],
        'peringatanStok': 'masih perlu diopname',
      });
      expect(hasil, ['masih perlu diopname']);
    });
  });

  group('tidak ada peringatan', () {
    test('respons biasa menghasilkan daftar kosong', () {
      expect(PeringatanTransaksi.dari({'status': '00'}), isEmpty);
      expect(PeringatanTransaksi.gabung({'status': '00'}), '');
    });

    test('null aman', () {
      expect(PeringatanTransaksi.dari(null), isEmpty);
      expect(PeringatanTransaksi.gabung(null), '');
    });

    test('bentuk tak terduga tidak melempar', () {
      // Respons rusak tidak boleh menggagalkan penampilan struk: transaksinya
      // sendiri sudah tersimpan.
      expect(PeringatanTransaksi.dari({'peringatanTransaksi': 'bukan daftar'}),
          isEmpty);
      expect(PeringatanTransaksi.dari({'peringatanTransaksi': 42}), isEmpty);
    });
  });
}
