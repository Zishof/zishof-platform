import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/transaksi_outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('klasifikasi retry transaksi pending', () {
    final service = TransaksiOutboxService.instance;

    test('gangguan jaringan dan server tanpa kode bisnis dicoba ulang', () {
      expect(
          service.dapatDicobaUlang(
              ApiException('timeout', offline: true, kode: '')),
          isTrue);
      expect(
          service.dapatDicobaUlang(
              ApiException('server error', statusHttp: 500, kode: 'SERVER')),
          isTrue);
      expect(
          service.dapatDicobaUlang(
              ApiException('jawaban rusak', statusHttp: 200, kode: '')),
          isTrue);
      expect(service.dapatDicobaUlang(StateError('internal client error')),
          isTrue);
    });

    test('penolakan bisnis berkode tidak dikirim berulang', () {
      expect(
          service.dapatDicobaUlang(ApiException('stok tidak cukup',
              statusHttp: 200, kode: 'STOK_TIDAK_CUKUP')),
          isFalse);
    });

    test('saldo tidak cukup tanpa kode tidak dikirim berulang', () {
      expect(
          service.dapatDicobaUlang(ApiException(
              'Saldo SAHRUL ARIFIN tidak mencukupi. Saldo saat ini Rp3.160, transaksi ini memotong Rp149.500.',
              statusHttp: 200)),
          isFalse);
    });

    test('kalimat saldo pada HTTP 522 tetap dianggap gangguan teknis', () {
      expect(
          service.dapatDicobaUlang(ApiException(
              'Gateway gagal ketika memeriksa saldo.',
              statusHttp: 522)),
          isTrue);
    });
  });
}
