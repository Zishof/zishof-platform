import 'package:ebisnis/screens/anggota/tab_saldo_voucher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saldo resmi server mengalahkan saldo berjalan mentah', () {
    final hasil = rekapSaldoVoucherDariMutasi([
      {
        'idAnggota': 1,
        'namaAnggota': 'Member Uji',
        'saldoAwal': 23500,
        'saldoPerPenabung': 223500,
        'saldoAwalResmi': 0,
        'saldoAkhirResmi': 200000,
        'masuk': 200000,
        'keluar': 0,
      }
    ]);

    expect(hasil, hasLength(1));
    expect(hasil.single['saldoAwal'], 0);
    expect(hasil.single['masuk'], 200000);
    expect(hasil.single['keluar'], 0);
    expect(hasil.single['saldoAkhir'], 200000);
  });

  test('kedaluwarsa dalam periode direkonsiliasi sebagai saldo keluar', () {
    final hasil = rekapSaldoVoucherDariMutasi([
      {
        'idAnggota': 1,
        'namaAnggota': 'Member Uji',
        'saldoAwalResmi': 45000,
        'saldoAkhirResmi': 0,
        'masuk': 0,
        'keluar': 21500,
      }
    ]);

    expect(hasil.single['saldoAwal'], 45000);
    expect(hasil.single['keluar'], 45000);
    expect(hasil.single['saldoAkhir'], 0);
  });

  test('fallback server lama mempertahankan perilaku sebelumnya', () {
    final hasil = rekapSaldoVoucherDariMutasi([
      {
        'idAnggota': 1,
        'namaAnggota': 'Member Uji',
        'saldoAwal': 10000,
        'saldoPerPenabung': 25000,
        'masuk': 15000,
        'keluar': 0,
      }
    ]);

    expect(hasil.single['saldoAwal'], 10000);
    expect(hasil.single['saldoAkhir'], 25000);
  });
}
