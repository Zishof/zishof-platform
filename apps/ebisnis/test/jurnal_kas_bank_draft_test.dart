import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/services/jurnal_kas_bank.dart';

void main() {
  test('pengeluaran membentuk biaya debet dan kas kredit seimbang', () {
    final baris = JurnalKasBankDraft.buat(
      pengeluaran: true,
      akunKasBank: 10,
      akunPasangan: 20,
      nominal: 12500,
      keterangan: 'Pembelian perlengkapan',
    );
    expect(baris, hasLength(2));
    expect(baris[0], containsPair('akunId', 20));
    expect(baris[0], containsPair('debet', 12500.0));
    expect(baris[1], containsPair('akunId', 10));
    expect(baris[1], containsPair('kredit', 12500.0));
  });

  test('pemasukan membentuk kas debet dan sumber kredit seimbang', () {
    final baris = JurnalKasBankDraft.buat(
      pengeluaran: false,
      akunKasBank: 10,
      akunPasangan: 20,
      nominal: 50000,
      keterangan: 'Penerimaan',
    );
    expect(baris, hasLength(2));
    expect(baris[0], containsPair('akunId', 10));
    expect(baris[0], containsPair('debet', 50000.0));
    expect(baris[1], containsPair('akunId', 20));
    expect(baris[1], containsPair('kredit', 50000.0));
  });

  test('menolak akun sama, nominal tidak sah, dan keterangan kosong', () {
    expect(
        () => JurnalKasBankDraft.buat(
            pengeluaran: true,
            akunKasBank: 1,
            akunPasangan: 1,
            nominal: 100,
            keterangan: 'x'),
        throwsArgumentError);
    expect(
        () => JurnalKasBankDraft.buat(
            pengeluaran: false,
            akunKasBank: 1,
            akunPasangan: 2,
            nominal: 0,
            keterangan: 'x'),
        throwsArgumentError);
    expect(
        () => JurnalKasBankDraft.buat(
            pengeluaran: false,
            akunKasBank: 1,
            akunPasangan: 2,
            nominal: 100,
            keterangan: '  '),
        throwsArgumentError);
  });
}
