import 'dart:io';

import 'package:ebisnis/services/validasi_saldo_pembayaran.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validasi saldo sebelum checkout', () {
    test('saldo yang sama dengan nominal dinilai cukup', () {
      final hasil = ValidasiSaldoPembayaran.evaluasi(
        saldo: 149500,
        nominal: 149500,
      );
      expect(hasil.mencukupi, isTrue);
      expect(hasil.kekurangan, 0);
    });

    test('saldo lama 3.100 memblokir transaksi 149.500', () {
      final hasil = ValidasiSaldoPembayaran.evaluasi(
        saldo: 3100,
        nominal: 149500,
      );
      expect(hasil.mencukupi, isFalse);
      expect(hasil.kekurangan, 146400);
    });

    test('split hanya membandingkan nominal yang memotong saldo', () {
      final hasil = ValidasiSaldoPembayaran.evaluasi(
        saldo: 50000,
        nominal: 40000,
      );
      expect(hasil.mencukupi, isTrue);
      expect(hasil.kekurangan, 0);
    });

    test('nilai tidak valid ditolak', () {
      expect(
        () => ValidasiSaldoPembayaran.evaluasi(saldo: -1, nominal: 1000),
        throwsArgumentError,
      );
      expect(
        () => ValidasiSaldoPembayaran.evaluasi(saldo: 1000, nominal: 0),
        throwsArgumentError,
      );
    });
  });

  test('preflight berada sebelum kode transaksi dan penyimpanan pending', () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    final mulai = source.indexOf('Future<void> _bayar() async');
    final selesai = source.indexOf('Future<void> _pilihMetode()', mulai);
    expect(mulai, greaterThanOrEqualTo(0));
    expect(selesai, greaterThan(mulai));
    final bayar = source.substring(mulai, selesai);

    final preflight = bayar.indexOf('await _validasiSaldoPusatSebelumBayar()');
    final kode = bayar.indexOf('await _buatKodeUnik()');
    final kirim = bayar.indexOf("aksi('bayar', payload)");
    final pending =
        bayar.indexOf('await CoreDb.instance.simpanTransaksiPending');
    expect(preflight, greaterThanOrEqualTo(0));
    expect(kode, greaterThan(preflight));
    expect(kirim, greaterThan(kode));
    expect(pending, greaterThan(kirim));
  });
}
