import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semua tabel laporan memakai kolom flex yang memenuhi lebar layar', () {
    final source =
        File('lib/screens/laporan_detail_screen.dart').readAsStringSync();

    expect(source, contains('int _flexKolom('));
    expect(source, contains('flex: _flexKolom(kolom[i], i)'));
    expect(source, contains('flex: _flexKolom(entry.value, entry.key)'));
    expect(source, isNot(contains('width: _lebarKolom,')));
  });

  test('sel angka clickable memenuhi seluruh lebar kolom', () {
    final source =
        File('lib/screens/laporan_detail_screen.dart').readAsStringSync();

    expect(source, contains('class _SelAngkaRincian'));
    expect(source, contains('width: double.infinity'));
    expect(source, contains('Klik untuk melihat data penghitungannya'));
  });
}
