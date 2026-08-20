import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak layar Konfigurasi Kode Akun terhadap API server (KodeAkunApiHelper):
/// nama aksi tulis dan kunci payload WAJIB persis, karena salah nama aksi hanya
/// terlihat saat tombol ditekan di produksi. Pola sama dgn
/// grup_produk_kontrak_api_test.dart (source-contract; ApiClient singleton tidak
/// injectable untuk widget test ber-mock).
void main() {
  final source = File('lib/screens/kode_akun_screen.dart').readAsStringSync();

  test('lima tab memakai aksi tulis kanonis milik KodeAkunApiHelper', () {
    for (final aksi in [
      'kode_akun_simpan',
      'kode_akun_hapus',
      'kode_akun_bank_simpan',
      'kode_akun_bank_hapus',
      'kode_akun_jenis_transaksi_simpan',
      'kode_akun_jenis_transaksi_hapus',
      'kode_akun_grup_simpan',
      'kode_akun_grup_hapus',
    ]) {
      expect(source, contains("'$aksi'"), reason: 'aksi $aksi');
    }
  });

  test('payload Akun memakai kunci yang divalidasi server', () {
    // Server menolak bila salah satunya hilang: kode/nama wajib, debetCredit dan
    // grupAkunId wajib dipilih, parentId menentukan hierarki (tombol Tambah Anak).
    for (final kunci in [
      "'kode'",
      "'nama'",
      "'debetCredit'",
      "'grupAkunId'",
      "'parentId'",
      "'aktifitas'",
      "'bankId'",
      "'atasNama'",
      "'noRek'",
    ]) {
      expect(source, contains(kunci), reason: 'payload $kunci');
    }
  });

  test('tombol mengikuti hak akses yang dikirim server', () {
    // Hak datang dari balasan daftar (grid CRUD TbmroleAction). Server tetap
    // gerbang sebenarnya; klien hanya menyembunyikan tombol yang pasti ditolak.
    expect(source, contains("res['hak']"));
    for (final aksi in ["'create'", "'update'", "'delete'"]) {
      expect(source, contains(aksi), reason: 'hak $aksi');
    }
    expect(source, contains('_bolehTambahTabIni'));
  });

  test('kode akun anak memakai panjang dari server, bukan angka mati', () {
    // Padanan properti akun_lenght pada layar ZK: kode anak = kode induk + N nol.
    expect(source, contains("res['panjangKodeAnak']"));
    expect(source, contains("'0' * _panjangKodeAnak"));
  });

  test('baca cache-dulu; mutasi lokal-dulu dgn id sementara', () {
    // Membaca offline aman dan membuat layar tetap terbuka saat jaringan mati.
    expect(source, contains('MasterOffline.daftarCacheDulu('));
    // Mutasi ditulis lokal dulu; keberatan spec 13.3 (jurnal mengacu akun tak
    // dikenal) ditangani id sementara yang ditukar saat sinkron.
    expect(source, contains('prosesSimpanMaster('));
    expect(source, contains('MasterOffline.idSementaraBaru()'));
    expect(source, contains('idLokal:'));
  });

  test('menu akuntansi digerbangi kunci fail-closed di kedua platform', () {
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    for (final kunci in [
      'kode_akun',
      'grup_akun',
      'jenis_transaksi',
      'bank_akun',
      'saldo_awal_akun',
      'jurnal_penyesuaian',
      'tutup_buku',
      'posting_kulakan',
      'posting_bayar_hutang',
      'posting_terima_piutang',
    ]) {
      expect(drawer, contains("bolehMenuVarianBaru('$kunci')"), reason: 'drawer $kunci');
      expect(shell, contains("'$kunci'"), reason: 'sidebar $kunci');
    }
  });
}
