import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak sisi klien grup "Keuangan": dasbor, cetak, tulis lokal-dulu, dan
/// penghapusan yang di perangkat bersifat SOFT (barisnya ditandai, bukan dibuang)
/// sehingga datanya masih bisa dipulihkan. Di server penghapusannya sungguhan --
/// riwayatnya ada pada audit trail server.
void main() {
  final layar = {
    'Uang Muka': File('lib/screens/uang_muka_screen.dart').readAsStringSync(),
    'PJ Uang Muka': File('lib/screens/pj_uang_muka_screen.dart').readAsStringSync(),
    'Kas Besar': File('lib/screens/kas_besar_screen.dart').readAsStringSync(),
    'PJ Kas Besar': File('lib/screens/pj_kas_besar_screen.dart').readAsStringSync(),
    'Kas Kecil': File('lib/screens/kas_kecil_screen.dart').readAsStringSync(),
  };

  layar.forEach((nama, source) {
    group(nama, () {
      test('membaca salinan lokal dulu', () {
        expect(source, contains('MasterOffline.daftarCacheDulu('));
        expect(source, contains('_cacheKey'));
      });

      test('create/edit/hapus ditulis lokal dulu, bukan langsung ke server', () {
        expect(source, contains('prosesSimpanMaster('));
        expect(source, contains('_kirimLokalDulu('));
        // Tidak boleh ada lagi jalur tulis yang menembak server langsung.
        expect(source, isNot(contains('await ApiClient.instance.aksi(\'uang_muka_simpan')));
        expect(source, isNot(contains('await ApiClient.instance.aksi(\'pj_uang_muka_simpan')));
        // Baris baru yang dibuat offline membawa id sementaranya sendiri.
        expect(source, contains('MasterOffline.idSementaraBaru()'));
        expect(source, contains('idLokal:'));
      });

      test('hapus bersifat soft di perangkat + dapat dibatalkan', () {
        // Penandaannya diserahkan ke MasterOffline (mekanisme bersama): baris
        // ditandai `_dihapus`, disaring dari daftar, dan pembatalannya IKUT
        // membuang perintah hapus yang masih mengantre -- tanpa itu baris kembali
        // tampil tetapi tetap terhapus di server begitu jaringan tersambung.
        expect(source, contains('hapusLokal: true'));
        expect(source, contains('MasterOffline.pulihkanLokal('));
        expect(source, contains('MasterOffline.daftarTerhapusLokal('));
        // Daftar utama menyembunyikannya; ada penyaring khusus untuk melihatnya.
        expect(source, contains('_terlihat'));
        expect(source, contains('_tampilkanTerhapus'));
      });

      test('punya tab Dasbor dan tombol Cetak seperti menu Pengadaan', () {
        expect(source, contains('PengadaanDasborTab('));
        expect(source, contains("aksi: 'keuangan_dasbor'"));
        expect(source, contains("namaParam: 'modul'"));
        expect(source, contains('cetakDokumenKeuangan('));
      });
    });
  });

  test('widget dasbor dipakai ulang, bukan diduplikasi', () {
    final tab = File('lib/screens/pengadaan_dasbor_tab.dart').readAsStringSync();
    // Aksi & nama parameternya kini dapat diatur, sehingga grup menu lain memakai
    // widget yang sama persis dengan Pengadaan.
    expect(tab, contains('this.aksi ='));
    expect(tab, contains('this.namaParam ='));
    expect(tab, contains('widget.aksi'));
    expect(tab, contains('widget.namaParam'));
  });

  test('cetak Keuangan memakai jendela pratinjau yang sama dengan Pengadaan', () {
    final util = File('lib/screens/keuangan_cetak_util.dart').readAsStringSync();
    expect(util, contains("'keuangan_cetak'"));
    expect(util, contains('tampilkanPratinjauPdf('));
  });
}
