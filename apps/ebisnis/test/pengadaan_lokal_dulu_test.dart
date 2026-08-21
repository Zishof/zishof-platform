import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Modul Pengadaan: seluruh MUTASI ditulis lokal dulu.
///
/// Pencocokan dilakukan pada salinan sumber yang spasinya dirapatkan supaya
/// pemenggalan baris oleh `dart format` tidak menggagalkan penjaga ini.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

String _sumber(String berkas) =>
    _rapat(File('lib/screens/$berkas').readAsStringSync());

void main() {
  // berkas : aksi mutasi yang WAJIB lewat jalur lokal-dulu
  const mutasi = <String, List<String>>{
    'pengadaan_pr_screen.dart': ['pengadaan_pr_simpan', 'pengadaan_pr_hapus'],
    'pengadaan_po_screen.dart': ['pengadaan_po_simpan', 'pengadaan_po_hapus'],
    'pengadaan_bast_screen.dart': [
      'pengadaan_bast_simpan',
      'pengadaan_bast_hapus',
      'pengadaan_bast_sinkron_kulakan',
    ],
    'pengadaan_bayar_screen.dart': [
      'pengadaan_bayar_simpan',
      'pengadaan_bayar_hapus',
      'pengadaan_bayar_putusan',
    ],
    'pengadaan_pajak_screen.dart': [
      'pengadaan_pajak_setor',
      'pengadaan_pajak_batal',
    ],
    'pengadaan_tagihan_screen.dart': ['pengadaan_lampiran_hapus'],
    'pengadaan_transitori_tab.dart': ['pengadaan_transitori_realisasi'],
  };

  test('setiap mutasi Pengadaan memakai jalur lokal-dulu', () {
    for (final entri in mutasi.entries) {
      final source = _sumber(entri.key);
      expect(source, contains(_rapat('prosesSimpanMaster(')),
          reason: '${entri.key} belum memakai jalur simpan lokal-dulu');
      for (final aksi in entri.value) {
        expect(source, contains(_rapat("'$aksi'")),
            reason: '${entri.key} kehilangan aksi $aksi');
        // Tidak boleh ada lagi pemanggilan LANGSUNG untuk aksi mutasi itu.
        expect(
            source, isNot(contains(_rapat("ApiClient.instance.aksi('$aksi'"))),
            reason: '$aksi kembali dikirim langsung tanpa antrean');
      }
    }
  });

  test('layar bertahap Pengadaan membaca daftarnya cache-dulu', () {
    for (final berkas in [
      'pengadaan_pr_screen.dart',
      'pengadaan_po_screen.dart',
      'pengadaan_bast_screen.dart',
      'pengadaan_tagihan_screen.dart',
      'pengadaan_bayar_screen.dart',
      'pengadaan_bdp_screen.dart',
    ]) {
      expect(_sumber(berkas), contains(_rapat('daftarCacheDulu(')),
          reason: '$berkas belum membaca salinan lokal lebih dulu');
    }
  });

  test('unggah/unduh lampiran & cetak tetap online-only', () {
    // Berkas biner tidak punya bentuk lokal yang berarti: mengantrekannya hanya
    // menunda kegagalan, bukan menyelamatkan data.
    final tagihan = _sumber('pengadaan_tagihan_screen.dart');
    expect(
        tagihan,
        contains(
            _rapat("ApiClient.instance.aksi('pengadaan_lampiran_unggah'")));
    expect(_sumber('pengadaan_cetak_util.dart'),
        contains(_rapat("ApiClient.instance.aksi('pengadaan_cetak'")));
  });
}
