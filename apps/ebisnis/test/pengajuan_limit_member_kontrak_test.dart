import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tab pengajuan limit tersedia dan daftar dibaca local-first', () {
    final host = File('lib/screens/anggota_screen.dart').readAsStringSync();
    final tab =
        File('lib/screens/anggota/tab_pengajuan_limit.dart').readAsStringSync();

    expect(host, contains('Pengajuan Melebihi Limit'));
    expect(host, contains('AnggotaTabPengajuanLimit'));
    expect(tab, contains('MasterOffline.daftarCacheDulu'));
    expect(tab, contains("'pengajuan_limit_member_list'"));
    expect(tab, contains("'pengajuan_limit_member_putuskan'"));
    expect(tab, contains('Sesi.instance.bolehVerifikasiLimitMember'));
  });

  test('persetujuan mengirim ulang transaksi lokal dengan kode yang sama', () {
    final tab =
        File('lib/screens/anggota/tab_pengajuan_limit.dart').readAsStringSync();
    final kasir = File('lib/screens/keranjang_screen.dart').readAsStringSync();

    expect(tab, contains('kirimSatuManual'));
    expect(tab, contains("row['kodeTransaksi']"));
    expect(kasir, contains('_kodePengajuanLimitTertunda'));
    expect(kasir, contains("e.kode == 'PENGAJUAN_LIMIT_MENUNGGU'"));
    expect(
      kasir,
      contains('_kodePengajuanLimitTertunda ?? await _buatKodeUnik()'),
    );
    expect(kasir, contains("pesanLimit.contains('ditolak')"));
    expect(kasir, contains("pesanLimit.contains('berbeda')"));
  });

  test('hak verifikasi limit dapat diatur dari layar Hak Akses', () {
    final hakAkses =
        File('lib/screens/hak_akses_screen.dart').readAsStringSync();

    expect(hakAkses, contains("hasil['bolehVerifikasiLimitMember']"));
    expect(hakAkses, contains("'bolehVerifikasiLimitMember':"));
    expect(hakAkses, contains('Boleh memverifikasi transaksi melebihi limit'));
  });

  test('saldo voucher memprioritaskan server dan menandai cache offline', () {
    final saldo =
        File('lib/screens/anggota/tab_saldo_voucher.dart').readAsStringSync();

    expect(saldo, contains('MasterOffline.daftarDenganCache'));
    expect(saldo, contains("res['offline'] == true"));
    expect(saldo, contains('Data server diperbarui'));
    expect(saldo, contains('Data offline - menampilkan cache terakhir'));
  });
}
