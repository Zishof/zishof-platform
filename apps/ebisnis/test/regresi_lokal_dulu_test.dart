import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga REGRESI: layar yang lahir sesudah sapuan local-first ikut memakai
/// jalur antrean.
///
/// Sapuan pertama menutup seluruh mutasi yang ada saat itu, tetapi layar baru
/// terus bertambah — dan tiap layar baru mulai dari nol lagi. Penjaga ini
/// mengunci layar-layar yang sudah dikonversi supaya tidak diam-diam kembali
/// mengirim langsung.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

String _layar(String berkas) =>
    _rapat(File('lib/screens/$berkas').readAsStringSync());

void main() {
  const mutasi = <String, List<String>>{
    // Aturan harga grosir = data master; kasir menyuntingnya di lapangan.
    'harga_grosir_editor.dart': ['harga_grosir_simpan', 'harga_grosir_hapus'],
    // Dokumen produksi dikerjakan di gudang, tempat paling sering tanpa sinyal.
    'produksi_screen.dart': ['produksi_simpan'],
    // Dokumen pengiriman diisi di jalan.
    'pengiriman_screen.dart': ['distribusi_simpan'],
  };

  test('mutasi layar baru memakai jalur lokal-dulu', () {
    for (final e in mutasi.entries) {
      final s = _layar(e.key);
      expect(s, contains(_rapat('prosesSimpanMaster(')),
          reason: '${e.key} tidak memakai jalur antrean');
      for (final aksi in e.value) {
        expect(s, isNot(contains(_rapat("ApiClient.instance.aksi('$aksi'"))),
            reason: '$aksi kembali dikirim langsung');
      }
    }
  });

  test('kunci antrean membedakan dokumen, bukan satu kunci untuk semua', () {
    // Kunci yang sama untuk dua dokumen berbeda membuat yang kedua MEMBUANG yang
    // pertama dari antrean — pekerjaan hilang tanpa pesan apa pun.
    expect(_layar('produksi_screen.dart'),
        contains(_rapat("kunci: 'produksi:\${widget.cfg.kode}:")));
    expect(_layar('pengiriman_screen.dart'),
        contains(_rapat("kunci: 'distribusi:\${widget.konfigurasi.kode}:")));
    expect(_layar('harga_grosir_editor.dart'),
        contains(_rapat("kunci: 'harga_grosir:\${widget.produkId}:")));
  });

  test('yang sengaja online punya alasan tertulis di tempatnya', () {
    // Tanpa catatan ini, sapuan berikutnya menandainya "belum local-first" lagi
    // dan seseorang akan mengantrekannya tanpa tahu mengapa dulu tidak boleh.
    const wajibBeralasan = <String, String>{
      'anggota/tab_data_member.dart': 'anggota_pin_simpan_massal',
      'anggota/member_biometric_panel.dart': 'biometrik_simpan',
      'anggota/tab_topup.dart': 'topup_online_buat',
      'anggota/tab_pengajuan_limit.dart': 'pengajuan_limit_member_putuskan',
    };
    for (final e in wajibBeralasan.entries) {
      final isi = File('lib/screens/${e.key}').readAsStringSync();
      final i = isi.indexOf(e.value);
      expect(i, greaterThan(0), reason: '${e.value} tidak ditemukan');
      final sebelum = isi.substring((i - 600).clamp(0, i), i);
      expect(sebelum, contains('ONLINE-ONLY'),
          reason: '${e.value} dikirim langsung tanpa alasan tertulis');
    }
  });
}
