import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checkout dikunci sebelum dialog dan dibuka kembali lewat finally', () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    final mulai = source.indexOf('Future<void> _bayar() async');
    final selesai = source.indexOf('Future<void> _pilihMetode()', mulai);
    expect(mulai, greaterThanOrEqualTo(0));
    expect(selesai, greaterThan(mulai));
    final bayar = source.substring(mulai, selesai);

    final cekKunci = bayar.indexOf('if (_ketukanBayarTerkunci) return;');
    final pasangKunci = bayar.indexOf('_ketukanBayarTerkunci = true;');
    final dialog = bayar.indexOf('await showDialog<bool>');
    final bukaKunci = bayar.lastIndexOf('_ketukanBayarTerkunci = false;');
    expect(cekKunci, greaterThanOrEqualTo(0));
    expect(pasangKunci, greaterThan(cekKunci));
    expect(dialog, greaterThan(pasangKunci));
    expect(bukaKunci, greaterThan(dialog));
    expect(bayar.substring(bukaKunci - 30, bukaKunci), contains('finally'));
  });
}
