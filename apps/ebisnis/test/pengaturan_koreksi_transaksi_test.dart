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

  test('supervisor dapat mengaktifkan koreksi toko dari dialog detail', () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains("hasil['bolehAktifkanKebijakanEditTransaksi']"));
    expect(source, contains('Aktifkan Koreksi Toko'));
    expect(source, contains("'pengaturan_edit_transaksi_toko_aktifkan'"));
    expect(source, contains('Online-only: kebijakan ini membuka koreksi'));
    expect(source, contains('if (aktif && mounted) await _lihatDetail(row)'));
  });

  test('penjelasan koreksi menyebut audit faktual, bukan format JSON', () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains('riwayat audit sebelum/sesudah beserta alasan'));
    expect(source, isNot(contains('audit JSON')));
  });

  test('koreksi lain tidak meratakan split-payment tanpa pilihan pengguna', () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains('bool _caraBayarDiubah = false'));
    expect(source, contains('_caraBayarDiubah = true'));
    expect(source, contains('if (widget.modeBaru || _caraBayarDiubah)'));
    expect(source, contains("if (hasilEdit.containsKey('cara_bayar'))"));
  });

  test('supervisor dapat mengganti alokasi dengan beberapa metode pembayaran',
      () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains('PemilihMetodeSplit'));
    expect(source, contains('sampai 5 metode'));
    expect(source, contains("if (hasilEdit.containsKey('pembayaran'))"));
    expect(source, contains("'nominal': slot.nominal"));
  });
}
