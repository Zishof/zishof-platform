import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak layar **Draft Jurnal** terhadap server (`DraftJurnalApiHelper` +
/// `DraftJurnalRingkasanUtil`, SVN ^/src) dan terhadap pendaftaran menunya.
///
/// Pola source-contract seperti `uang_muka_kontrak_test.dart`: ApiClient singleton
/// tidak injectable untuk widget test, jadi yang dikunci adalah nama aksi, kunci
/// payload/respons, dan titik daftar menu -- persis hal-hal yang diam-diam bisa
/// menyimpang saat salah satu sisi diubah.
void main() {
  test('layar Draft Jurnal memakai aksi dan kunci respons kontrak server', () {
    final source =
        File('lib/screens/draft_jurnal_screen.dart').readAsStringSync();

    expect(source, contains("aksi('draft_jurnal_ringkasan'"));
    // Payload rentang tanggal: kontraknya yyyy-MM-dd (lihat DraftJurnalApiHelper.iso).
    expect(source, contains("'mulai'"));
    expect(source, contains("'sampai'"));
    expect(source, contains("DateFormat('yyyy-MM-dd')"));

    // Kunci respons yang dipakai kartu ringkasan dan tabel.
    for (final kunci in ["'data'", "'draft'", "'posting'", "'closing'"]) {
      expect(source, contains(kunci), reason: 'kunci respons $kunci hilang');
    }
    for (final kolom in ["'nama'", "'keterangan'"]) {
      expect(source, contains(kolom), reason: 'kolom baris $kolom hilang');
    }

    // Permintaan pengguna: tanpa webview/iframe -- seluruh isinya dirender natif.
    expect(source.contains('WebView'), isFalse);
    expect(source.contains('InAppWebView'), isFalse);
    expect(source.contains('url_launcher'), isFalse);
  });

  test('rincian memakai aksi dan kunci payload kontrak server', () {
    final source =
        File('lib/screens/draft_jurnal_screen.dart').readAsStringSync();

    expect(source, contains("aksi('draft_jurnal_rincian'"));
    // Server membangun daftar dari kriteria yang sama dgn angkanya, dikenali lewat
    // nama baris + status; ketiganya wajib ikut terkirim.
    expect(source, contains("'nama': widget.nama"));
    expect(source, contains("'status': widget.status"));
    expect(source, contains("'mulai': widget.mulai"));
    expect(source, contains("'sampai': widget.sampai"));

    // Status yang dikenal server hanya tiga -- lihat DraftJurnalApiHelper.rincian.
    for (final status in ["'draft'", "'posting'", "'closing'"]) {
      expect(source, contains(status), reason: 'status $status hilang');
    }
  });

  test('posting massal memakai aksi kontrak dan hanya tampil bila ada mesinnya',
      () {
    final source =
        File('lib/screens/draft_jurnal_screen.dart').readAsStringSync();

    expect(source, contains("'draft_jurnal_posting'"));
    expect(source, contains("'draft_jurnal_batal_posting'"));

    // Tombol hanya ditawarkan bila server menyatakan modulnya punya mesin posting;
    // tombol yang ujungnya menolak sama saja dgn janji kosong.
    expect(source, contains("baris['bisaPosting'] != true"));

    // Dua aksi ini menulis (dan menghapus) jurnal: konfirmasi wajib ada.
    expect(source, contains('Konfirmasi Posting'));
    expect(source, contains('Konfirmasi Batalkan Posting'));
    expect(source, contains('SUDAH closing tidak akan dibatalkan'));
  });

  test('menu Draft Jurnal terdaftar di kedua platform', () {
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();

    // Desktop: enum, kunci hak akses, item menu, grup Akuntansi, dan builder layar.
    expect(shell, contains('draftJurnal,'));
    expect(shell, contains("MenuEBisnis.draftJurnal: 'draft_jurnal'"));
    expect(shell, contains("'Draft Jurnal'"));
    expect(shell, contains('_bangunDraftJurnal'));
    expect(shell, contains('DraftJurnalScreen()'));

    // Android/mobile: item pada grup Akuntansi di drawer, dengan gerbang yang sama.
    expect(drawer, contains("bolehMenuVarianBaru('draft_jurnal')"));
    expect(drawer, contains('DraftJurnalScreen()'));
  });
}
