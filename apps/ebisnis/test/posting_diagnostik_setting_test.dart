import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('posting penjualan menampilkan rincian setting, bukan hanya jumlah', () {
    final source = File('lib/screens/laporan_screen.dart').readAsStringSync();

    expect(source, contains('_diagnostikPemetaan(belum)'));
    expect(source, contains('Yang perlu dilakukan:'));
    expect(source, contains('klik Pratinjau lagi'));
    expect(source, contains('tidak boleh dipaksa posting'));
    expect(source, contains('SelectableText'));
    expect(
        source,
        isNot(
            contains("Text('\${belum.length} pemetaan akun belum lengkap.'")));
  });

  test('semua posting toko menampilkan alasan dan tindakan per dokumen', () {
    final source =
        File('lib/screens/posting_toko_dialog.dart').readAsStringSync();

    expect(source, contains('_diagnostikSetting(rincianBelum)'));
    expect(source, contains("r['referensi']"));
    expect(source, contains("r['alasan']"));
    expect(source, contains('Lengkapi master/akun yang disebutkan'));
    expect(source, contains('klik Muat ulang'));
  });
}
