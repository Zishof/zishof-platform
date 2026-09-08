import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _padat(String nilai) => nilai.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final screen = File('lib/screens/setup_laporan_screen.dart');
  final shell = File('lib/widgets/app_shell.dart');

  test('Setup Laporan tersedia pada satu source untuk Windows dan Android', () {
    final isi = _padat(screen.readAsStringSync());
    final navigasi = _padat(shell.readAsStringSync());

    expect(navigasi, contains('MenuEBisnis.setupLaporan'));
    expect(navigasi, contains("'Setup Laporan'"));
    expect(navigasi, contains("MenuEBisnis.setupLaporan: 'pemetaan_akun'"));
    expect(isi, contains("'pemetaan_akun_setup_daftar'"));
    expect(isi, contains("'batasAkun': 10000"));
  });

  test('daftar local-first tetapi seluruh mutasi pemetaan online-only', () {
    final isi = _padat(screen.readAsStringSync());
    expect(isi, contains('MasterOffline.daftarCacheDulu'));
    expect(isi, contains("'pemetaan_akun_setup_daftar'"));

    for (final aksi in [
      'pemetaan_akun_setup_kelompok_simpan',
      'pemetaan_akun_setup_akun_tambah',
      'pemetaan_akun_setup_akun_urut',
      'pemetaan_akun_setup_akun_hapus',
      'pemetaan_akun_setup_bersihkan',
      'pemetaan_akun_terapkan',
    ]) {
      expect(isi, contains("'$aksi'"), reason: aksi);
    }
    expect(isi, contains('Online-only: pemetaan memengaruhi angka laporan'));
    expect(
        isi, isNot(contains("MasterOffline.simpanAtauAntre( 'pemetaan_akun")));
  });

  test(
      'grid menjelaskan sumber data dan mencegah tampilan kosong membingungkan',
      () {
    final isi = screen.readAsStringSync();
    expect(isi, contains('Jenis Laporan -> Grup Laporan -> Sub Laporan'));
    expect(isi, contains('Belum ada akun pada kelompok ini'));
    expect(isi, contains('Petakan akun otomatis'));
    expect(isi, contains('Akun, jurnal, dan saldo tidak dihapus'));
    expect(isi, contains("'Kelompok laporan'"));
    expect(isi, contains("'Relasi akun'"));
    expect(isi, contains("'Belum terpetakan'"));
  });
}
