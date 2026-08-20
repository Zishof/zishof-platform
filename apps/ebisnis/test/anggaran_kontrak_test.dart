import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak layar Anggaran (RAB Bulanan) terhadap API server (`AnggaranApiHelper`) dan
/// terhadap logika empat layar ZK yang ditirunya: `workspace_bulanan.zul`,
/// `workspace_revisi_bulanan.zul`, `realisasi_bulanan.zul`, `penggunaan_anggaran.zul`.
///
/// Pola source-contract, sama dgn grup_produk_kontrak_api_test.dart: ApiClient singleton
/// tidak injectable untuk widget test ber-mock, sedangkan salah nama aksi baru terlihat
/// saat tombol ditekan di produksi.
void main() {
  final layar = File('lib/screens/anggaran_screen.dart').readAsStringSync();

  test('memakai aksi kanonis milik AnggaranApiHelper', () {
    for (final aksi in [
      'anggaran_konteks',
      'anggaran_revisi_list',
      'anggaran_item_list',
      'anggaran_item_simpan',
      'anggaran_item_hapus',
      'anggaran_revisi_baru',
      'anggaran_realisasi_list',
      'anggaran_penggunaan_list',
      'anggaran_penggunaan_simpan',
      'anggaran_penggunaan_hapus',
    ]) {
      expect(layar, contains("'$aksi'"), reason: 'aksi $aksi');
    }
  });

  test('penyaring sama dengan kepala halaman workspace_bulanan.zul', () {
    // Tahun Anggaran, Satuan Kerja, Sumber Dana, lalu Revisi -- empat penyaring itu
    // yang menentukan pohon mana yang tampil, persis seperti layar ZK.
    for (final label in [
      'Tahun Anggaran',
      'Satuan Kerja',
      'Sumber Dana',
      'Revisi',
      'Buat Revisi Baru',
    ]) {
      expect(layar, contains(label), reason: 'penyaring $label');
    }
    for (final kunci in ["'tahun'", "'satkerId'", "'sumberDanaId'", "'revisi'"]) {
      expect(layar, contains(kunci), reason: 'payload $kunci');
    }
  });

  test('rincian dua belas bulan ikut dikirim dan ditampilkan', () {
    expect(layar, contains("'bulan'"));
    expect(layar, contains('namaBulan'));
    // Dua belas kolom bulan pada tabel rencana (padanan bulan1..bulan12 pada Workspace).
    expect(layar, contains("for (var i = 0; i < 12; i++)"));
  });

  test('tiga tab: rencana, realisasi, penggunaan anggaran', () {
    expect(layar, contains('Rencana Bulanan'));
    expect(layar, contains('Realisasi'));
    expect(layar, contains('Penggunaan Anggaran'));
  });

  test('baris realisasi dari dokumen lain tidak boleh disunting di sini', () {
    // penggunaan_anggaran.zul: baris milik dokumen (uang muka, kas kecil, jurnal, dst)
    // harus dibatalkan dari dokumen asalnya supaya realisasi tetap sinkron.
    expect(layar, contains("'Entri Manual'"));
    expect(layar, contains('Icons.lock_outline'));
  });

  test('tombol mengikuti hak akses dari server', () {
    expect(layar, contains("res['hak']"));
    for (final aksi in ["'create'", "'update'", "'delete'"]) {
      expect(layar, contains(aksi), reason: 'hak $aksi');
    }
  });

  test('menu Anggaran terpasang fail-closed di kedua platform', () {
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    expect(drawer, contains("bolehMenuVarianBaru('anggaran')"));
    expect(shell, contains("MenuEBisnis.anggaran: 'anggaran'"));
    expect(shell, contains('MenuEBisnis.anggaran,'));
    expect(shell, contains("'Anggaran (RAB Bulanan)'"));
  });
}
