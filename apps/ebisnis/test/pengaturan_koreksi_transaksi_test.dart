import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaksi tersinkron meminta detail dan otorisasi terbaru dari server',
      () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains("row['statusSinkronLokal'] == 'SYNCED'"));
    expect(source, contains(".aksi('detail_transaksi'"));
    expect(source, contains("hasil['bolehEditTransaksi'] == true"));
    expect(source, isNot(contains('PengaturanKoreksiTransaksi.instance')));
  });

  test('snapshot offline hanya untuk membaca dan tidak memberi izin edit', () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains("'bolehEditTransaksi': false"));
    expect(source, contains('if (!error.offline'));
  });

  test('konfigurasi edit transaksi berasal dari server global dan per toko',
      () {
    final source =
        File('lib/screens/konfigurasi_screen.dart').readAsStringSync();

    expect(source, contains("'pengaturan_edit_transaksi_ambil'"));
    expect(source, contains("'pengaturan_edit_transaksi_global_simpan'"));
    expect(source, contains("'izinkan_edit_transaksi_toko'"));
    expect(source, contains('Kebijakan global server'));
  });
}
