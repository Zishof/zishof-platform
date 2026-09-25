import 'dart:io';

import 'package:ebisnis/services/hrd_local_first.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    Sesi.instance
      ..tenantId = null
      ..userId = '';
  });

  test('cache HRD terpisah menurut tenant pengguna aksi dan parameter', () {
    Sesi.instance
      ..tenantId = 11
      ..userId = 'Kasir@Contoh.ID';
    final awal = HrdLocalFirst.kunci(
        'hrd_pegawai_daftar', const {'page_size': 50, 'page': 1});
    final urutanBerbeda = HrdLocalFirst.kunci(
        'hrd_pegawai_daftar', const {'page': 1, 'page_size': 50});

    expect(awal, urutanBerbeda);
    expect(awal, contains('tenant-11'));
    expect(awal, contains('user-kasir@contoh.id'));

    Sesi.instance.tenantId = 12;
    expect(
        HrdLocalFirst.kunci(
            'hrd_pegawai_daftar', const {'page_size': 50, 'page': 1}),
        isNot(awal));

    Sesi.instance
      ..tenantId = 11
      ..userId = 'supervisor';
    expect(
        HrdLocalFirst.kunci(
            'hrd_pegawai_daftar', const {'page_size': 50, 'page': 1}),
        isNot(awal));
  });

  test('pembacaan HRD gagal tertutup tanpa konteks tenant atau pengguna', () {
    Sesi.instance
      ..tenantId = null
      ..userId = 'kasir';
    expect(() => HrdLocalFirst.kunci('hrd_master_daftar', const {}),
        throwsStateError);

    Sesi.instance
      ..tenantId = 11
      ..userId = '';
    expect(() => HrdLocalFirst.kunci('hrd_master_daftar', const {}),
        throwsStateError);
  });

  test('layar HRD memakai local-first dan aksi sensitif tetap online', () {
    final source = File('lib/screens/hrd_dasar_screen.dart').readAsStringSync();
    for (final aksi in const [
      'hrd_master_daftar',
      'hrd_pegawai_daftar',
      'hrd_pegawai_detail',
      'hrd_jenis_cuti_daftar',
      'hrd_cuti_daftar',
      'hrd_kehadiran_daftar',
      'hrd_kehadiran_ringkasan',
      'hrd_payroll_daftar',
      'hrd_slip_detail',
      'hrd_pengajuan_jenis',
      'hrd_pengajuan_daftar',
      'hrd_gaji_pokok_daftar',
      'hrd_kenaikan_gaji_daftar',
      'hrd_tugas_kinerja_daftar',
      'hrd_kinerja_daftar',
      'hrd_riwayat_pegawai',
    ]) {
      expect(source,
          matches(RegExp("HrdLocalFirst\\.baca\\([\\s\\S]{0,120}'$aksi'")),
          reason: aksi);
    }
    expect(source, contains(".aksi('hrd_cuti_simpan'"));
    expect(source, contains(".aksi('hrd_cuti_putusan'"));
    expect(source, contains("'hrd_pengajuan_putusan'"));
  });
}
