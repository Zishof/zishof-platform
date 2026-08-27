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
}
