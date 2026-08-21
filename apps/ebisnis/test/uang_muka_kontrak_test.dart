import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak layar Uang Muka terhadap `UangMukaApiHelper`: nama aksi dan kunci payload
/// WAJIB persis, karena salah nama hanya ketahuan saat tombol ditekan di produksi.
void main() {
  final source = File('lib/screens/uang_muka_screen.dart').readAsStringSync();

  test('memakai aksi kanonis milik UangMukaApiHelper', () {
    for (final aksi in [
      'uang_muka_opsi',
      'uang_muka_daftar',
      'uang_muka_simpan',
      'uang_muka_hapus',
      'uang_muka_setujui',
      'uang_muka_tolak',
      'uang_muka_saldo',
      'uang_muka_cari_anggaran',
    ]) {
      expect(source, contains("'$aksi'"), reason: 'aksi $aksi');
    }
  });

  test('payload memakai kunci yang divalidasi server', () {
    for (final kunci in [
      "'nama'",
      "'tanpaAnggaran'",
      "'ambilDariPr'",
      "'satuanKerjaId'",
      "'akunId'",
      "'workspaceId'",
      "'jenisUangMukaId'",
      "'nilai'",
      "'mulai'",
      "'sampai'",
      "'selesai'",
      "'statusDokumen'",
    ]) {
      expect(source, contains(kunci), reason: 'payload $kunci');
    }
  });

  test('tombol mengikuti hak akses per aksi yang dikirim server', () {
    // Termasuk approve/reject: menyetujui pencairan dana dipisah dari sekadar mengubah.
    expect(source, contains("hasil['hak']"));
    for (final aksi in ["'create'", "'update'", "'delete'", "'approve'", "'reject'"]) {
      expect(source, contains(aksi), reason: 'hak $aksi');
    }
  });

  test('dokumen yang sudah dijurnal dikunci di layar', () {
    // Server tetap menolak, tetapi tombolnya juga disembunyikan supaya tidak menyesatkan.
    expect(source, contains("b['sudahDijurnal']"));
  });

  test('penyaring sama dengan kepala halaman layar ZK', () {
    for (final kunci in ["'cari'", "'statusFilter'", "'dari'", "'sampai'", "'belumLpj'"]) {
      expect(source, contains(kunci), reason: 'penyaring $kunci');
    }
  });

  test('menu Uang Muka membuka layarnya di kedua platform', () {
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    expect(shell, contains('_bangunUangMuka'));
    expect(shell, contains('const UangMukaScreen()'));
    expect(drawer, contains('const UangMukaScreen()'));
    expect(drawer, isNot(contains("_belumTersedia(context, 'Uang Muka (Cash Advance)')")));
  });
}
