import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu HRD memakai kontrak API Pegawai Cuti dan Kehadiran', () {
    final layar = File('lib/screens/hrd_dasar_screen.dart').readAsStringSync();
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();

    for (final aksi in const [
      'hrd_master_daftar',
      'hrd_pegawai_daftar',
      'hrd_jenis_cuti_daftar',
      'hrd_cuti_daftar',
      'hrd_cuti_simpan',
      'hrd_cuti_putusan',
      'hrd_kehadiran_daftar',
      'hrd_kehadiran_ringkasan',
      'hrd_payroll_daftar',
      'hrd_slip_detail',
      'hrd_pengajuan_jenis',
      'hrd_pengajuan_daftar',
      'hrd_pengajuan_simpan',
      'hrd_pengajuan_putusan',
      'hrd_riwayat_simpan',
      'hrd_riwayat_hapus',
    ]) {
      expect(layar, contains("'$aksi'"));
    }
    expect(shell, contains('MenuEBisnis.hrdDasar'));
    expect(shell, contains("MenuEBisnis.hrdDasar: 'hrd_dasar'"));
    expect(shell, contains("_GrupMenuShell('SDM'"));
    expect(layar, contains('Ajukan Lembur / Kasbon'));
    expect(layar, contains('Kedisiplinan'));
    expect(layar, contains('Fingerprint:'));
    expect(layar, contains('Master HRD'));
    expect(layar, contains('Master organisasi dan jadwal kerja dari modul ZK'));
    expect(layar, contains("'hrd_riwayat_simpan'"));
    expect(layar, contains("'PENDIDIKAN'"));
    expect(layar, contains("'PELATIHAN'"));
    expect(layar, contains("'KELUARGA'"));
    expect(layar, contains("'PEKERJAAN'"));
    expect(layar, contains("'PELANGGARAN'"));
  });
}
