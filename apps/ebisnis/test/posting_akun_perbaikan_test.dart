import 'package:ebisnis/screens/posting_akun_perbaikan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sumber akun posting', () {
    test('Penjualan menjelaskan kas/piutang dan pendapatan', () {
      final sumber = sumberAkunPosting('penjualan');

      expect(sumber.debet, contains('Cara Pembayaran'));
      expect(sumber.debet, contains('Piutang Usaha'));
      expect(sumber.kredit, contains('Jenis Produk'));
      expect(sumber.kredit, contains('Akun Pendapatan'));
    });

    test('HPP menjelaskan relasi beban dan persediaan', () {
      final sumber = sumberAkunPosting('hpp');

      expect(sumber.debet, contains('Akun HPP'));
      expect(sumber.kredit, contains('Akun Persediaan'));
      expect(sumber.urutan, contains('Akun Persediaan harus sama'));
    });

    test('Kulakan membedakan pembelian kredit dan tunai', () {
      final sumber = sumberAkunPosting('kulakan');

      expect(sumber.debet, contains('Akun Persediaan'));
      expect(sumber.kredit, contains('Pembelian kredit'));
      expect(sumber.kredit, contains('Pembelian tunai'));
    });
  });

  group('pemetaan CRUD akun seluruh posting', () {
    test('penjualan mengarah ke Cara Pembayaran dan Jenis Produk', () {
      expect(
        targetCrudAkunPosting(
          jenis: 'penjualan',
          sisi: SisiAkunPosting.debet,
        ).map((e) => e.id),
        ['cara_bayar'],
      );
      expect(
        targetCrudAkunPosting(
          jenis: 'penjualan',
          sisi: SisiAkunPosting.kredit,
        ).map((e) => e.id),
        ['jenis_produk'],
      );
    });

    test('HPP menyediakan sumber HPP dan persediaan', () {
      expect(
        targetCrudAkunPosting(jenis: 'hpp', sisi: SisiAkunPosting.debet)
            .map((e) => e.id),
        containsAll(['jenis_produk', 'kelompok_aset']),
      );
      expect(
        targetCrudAkunPosting(jenis: 'hpp', sisi: SisiAkunPosting.kredit)
            .map((e) => e.id),
        containsAll(['master_aset', 'kelompok_aset']),
      );
    });

    test('kulakan, bayar hutang, dan terima piutang mencakup master sumber',
        () {
      expect(
        targetCrudAkunPosting(
          jenis: 'kulakan',
          sisi: SisiAkunPosting.kredit,
        ).map((e) => e.id),
        containsAll(['supplier', 'toko', 'cara_bayar']),
      );
      expect(
        targetCrudAkunPosting(
          jenis: 'bayar_hutang',
          sisi: SisiAkunPosting.debet,
        ).single.id,
        'supplier',
      );
      expect(
        targetCrudAkunPosting(
          jenis: 'terima_piutang',
          sisi: SisiAkunPosting.kredit,
        ).map((e) => e.id),
        contains('toko'),
      );
    });

    test('alasan transaksi menyempitkan form CRUD yang dibuka', () {
      expect(
        targetCrudAkunPosting(
          jenis: 'kulakan',
          sisi: SisiAkunPosting.kredit,
          alasan: 'Akun Utang supplier belum diatur pada master Penyedia.',
        ).single.id,
        'supplier',
      );
      expect(
        targetCrudAkunPosting(
          jenis: 'hpp',
          sisi: SisiAkunPosting.kredit,
          alasan: 'Akun persediaan belum diatur pada Master Aset.',
        ).map((e) => e.id),
        containsAll(['master_aset', 'kelompok_aset']),
      );
    });
  });
}
