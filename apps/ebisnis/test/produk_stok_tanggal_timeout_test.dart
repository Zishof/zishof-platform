import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prevent a failed date request from silently changing the stock report to today.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/produk_screen.dart').readAsStringSync();
  });

  test('a failed load preserves the selected stock date', () {
    final start = source.indexOf('Future<void> _muatStokTanggal()');
    final end = source.indexOf('Future<void> _pilihTanggalStok()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final loader = source.substring(start, end);
    expect(loader, contains('_galatStokTanggal = pesan'));
    expect(loader, isNot(contains('_tanggalStok = null')));
  });

  test('preview and retry keep the selected date and offer recovery', () {
    expect(source, contains('tanggal: tanggal, kataKunci: _kataKunci'));
    expect(source, contains("value: 'coba_lagi'"));
    expect(source, contains('unawaited(_muatStokTanggal())'));
  });

  test('does not show current stock as the requested historical quantity', () {
    expect(source, contains('stokTanggalBelumTersedia'));
    expect(source, contains("? '—'"));
    expect(source, contains("? 'Belum dimuat'"));
  });
}
