import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kasbon Divisi otomatis menjadi piutang customer dan meminta PIC', () {
    final cara = CaraBayar.fromJson({
      'id': 10,
      'kode': 'kasbon_divisi',
      'nama': 'Kasbon Divisi',
      'manual': true,
      'masukSebagaiHutang': false,
      // Payload lama/setting lama dapat mengirim false. Invariant Kasbon tetap
      // menang agar transaksi masuk sub-ledger piutang customer.
      'wajibPilihMember': false,
    });

    expect(cara.wajibPilihMember, isTrue);
    expect(cara.masukSebagaiHutang, isTrue);
  });

  test('metode biasa tidak dipaksa memakai PIC', () {
    final cara = CaraBayar.fromJson({
      'id': 11,
      'kode': '001',
      'nama': 'Transfer',
      'manual': true,
      'masukSebagaiHutang': false,
      'wajibPilihMember': false,
    });

    expect(cara.wajibPilihMember, isFalse);
  });

  test('kode lama KasbonOperasional tetap dikenali tanpa bergantung nama', () {
    final cara = CaraBayar.fromJson({
      'id': 12,
      'kode': 'KasbonOperasional',
      'nama': '',
      'manual': true,
      'masukSebagaiHutang': false,
      'wajibPilihMember': false,
    });

    expect(cara.wajibPilihMember, isTrue);
    expect(cara.masukSebagaiHutang, isTrue);
  });

  test('layar menjelaskan Kasbon sebagai piutang customer ber-PIC', () {
    final kasir = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    final master =
        File('lib/screens/cara_bayar_screen.dart').readAsStringSync();

    expect(kasir, contains('Pilih Member / PIC'));
    expect(kasir, contains('langsung dicatat sebagai piutang customer'));
    expect(master, contains('Penanggung Jawab (PIC)'));
    expect(master, contains('Semua Kasbon wajib memilih member'));
    expect(master, contains("AppTableColumn('Wajib PIC'"));
  });
}
