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

  group('diambil dari Permintaan Pengadaan (PR)', () {
    test('penandanya benar-benar memilih baris PR, bukan sekadar dicentang', () {
      // Sebelumnya penanda ini hanya boolean dan rinciannya harus dipilih di layar ZK.
      expect(source, contains("'uang_muka_cari_pr'"));
      expect(source, contains('_pilihBarisPr('));
      expect(source, contains("'prDetailIds'"));
      expect(source, isNot(contains('Rincian PR-nya dipilih di layar ZK')));
    });

    test('nilai pengajuan mengikuti jumlah baris PR terpilih', () {
      // Layar ZK mengisi kolom Nilai begitu PR dipilih; layar ini menyalinnya.
      expect(source, contains("nilai.text = t == 0 ? '' : "));
    });

    test('baris PR yang terkunci tidak bisa dicentang', () {
      // Baris yang barangnya sudah diterima penuh dikirim server dgn bolehPilih=false.
      expect(source, contains("b['bolehPilih'] == true"));
      expect(source, contains("b['alasanTerkunci']"));
      // Baris milik uang muka lain diberi peringatan, bukan dilarang -- sama dgn ZK.
      expect(source, contains("b['uangMukaKode']"));
    });

    test('anggaran & akun tidak diminta pada pengajuan berbasis PR', () {
      // Di ZK baris Anggaran hanya tampil bila bukan tanpaAnggaran DAN bukan dari PR,
      // sedangkan baris Akun hanya bila tanpaAnggaran DAN bukan dari PR.
      expect(source, contains('if (!tanpaAnggaran && !ambilDariPr) ...['));
      expect(source, contains('if (!ambilDariPr) ...['));
    });

    test('dokumen lama memuat ulang baris PR-nya saat disunting', () {
      expect(source, contains("b['milikDokumenIni'] == true"));
    });
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
