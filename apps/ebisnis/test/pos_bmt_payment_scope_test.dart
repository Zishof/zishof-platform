import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QRIS dan EDC manual tidak berubah menjadi tagihan Online BMT', () {
    for (final nama in ['QRIS BSI', 'QRIS BMT', 'EDC Merchant']) {
      final metode = CaraBayar.fromJson({
        'id': 1,
        'nama': nama,
        'manual': true,
        'online': false,
        // Respons/cache lama mungkin masih membawa flag BMT dari kanal toko.
        'onlineBmt': true,
        'memotongDeposit': false,
      });

      expect(metode.online, isFalse, reason: nama);
      expect(metode.onlineBmt, isFalse, reason: nama);
      expect(metode.memotongDepositEfektif, isFalse, reason: nama);
    }
  });

  test('tagihan BMT tetap tidak diaktifkan oleh flag kanal toko yang tersimpan',
      () {
    final metode = CaraBayar.fromJson({
      'id': 2,
      'nama': 'EDC Merchant',
      'manual': true,
      'onlineBmt': true,
    });

    expect(metode.onlineBmt, isFalse);
    expect(metode.online, isFalse);
  });

  test('checkout POS hanya membuka BMT dari tanda khusus yang diberikan server',
      () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    final start = source.indexOf('final bool metodeOnlineBmtAktif =');
    final end = source.indexOf(';', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final condition = source.substring(start, end);
    expect(condition, contains('_caraBayarTerpilih!.onlineBmt'));
    expect(condition, isNot(contains('_caraBayarTerpilih!.online;')));
  });
}
