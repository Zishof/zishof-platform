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
    // Membatalkan opname & keputusan QC: dokumen milik toko sendiri, tidak ada
    // pihak lain yang keputusannya dapat bertabrakan.
    'stok_opname_screen.dart': ['so_batalkan'],
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

  test('disposisi QC jujur soal dokumen turunan saat offline', () {
    // Dokumen turunan (rework/unbuild/scrap) dibuat SERVER saat perintahnya tiba.
    // Menyebut jumlahnya saat offline berarti mengarang angka yang belum tentu
    // benar; pesannya harus mengaku bahwa turunannya menyusul.
    final s = _layar('produksi_screen.dart');
    expect(s, contains(_rapat("r['offline'] == true")));
    expect(s, contains(_rapat('Dokumen turunannya dibuat setelah terkirim.')));
  });

  test('pembatalan opname tidak menebak stok akhir saat offline', () {
    // Stok akhir dihitung server; menebaknya di klien akan menampilkan angka
    // yang berbeda dari kenyataan sampai penyelarasan berikutnya berjalan.
    final s = _layar('stok_opname_screen.dart');
    expect(s, contains(_rapat("(hasil['produkId'] as num?)?.toInt()")));
    expect(s, contains(_rapat('prosesSimpanMaster(')));
  });

  test('daftarnya ikut dibaca cache-dulu, bukan hanya tulisannya', () {
    // Menyelamatkan tulisan tanpa menyelamatkan bacaan hanya setengah jalan:
    // offline layarnya KOSONG, jadi dokumen yang mau disunting pun tak terbuka.
    const bacaCache = <String, String>{
      'pengiriman_screen.dart': "'master:distribusi:\${konfigurasi.kode}'",
      'produksi_screen.dart': "'master:produksi:\${cfg.kode}'",
      'harga_grosir_editor.dart': "'master:harga_grosir:\${widget.produkId}'",
    };
    for (final e in bacaCache.entries) {
      final s = _layar(e.key);
      expect(s, contains(_rapat('daftarCacheDulu(')),
          reason: '${e.key} masih membaca daftarnya online-only');
      // Cache dipisah per JENIS/PRODUK: satu kunci untuk semua membuat daftar
      // yang satu tampil pada yang lain.
      expect(s, contains(_rapat(e.value)),
          reason: '${e.key} memakai kunci cache yang tidak membedakan');
    }
  });

  test('daftar master lain ikut cache-dulu', () {
    const bacaCache = <String, String>{
      'anggota/tab_satuan_kerja.dart': 'master:satuan_kerja:',
      'kulakan_bulk_entry_screen.dart': 'master:jenis_produk:massal',
      'price_tag_screen.dart': 'master:diskon_promo_price_tag',
    };
    for (final e in bacaCache.entries) {
      final isi = _rapat(File('lib/screens/${e.key}').readAsStringSync());
      expect(isi, contains(_rapat(e.value)),
          reason: '${e.key} masih membaca daftarnya online-only');
    }
  });

  test('antrean berjalan dan daftar hak akses TIDAK di-cache', () {
    // Dua-duanya sengaja: antrean resep yang basi membuat dua kasir melayani
    // resep yang sama, dan daftar hak akses yang basi menampilkan wewenang yang
    // sudah dicabut — padahal admin mengambil keputusan dari layar itu.
    const wajibOnline = <String, String>{
      'apotik/kasir_apotik_screen.dart': 'apotik_resep_list',
      'konfigurasi_screen.dart': 'hak_akses_list',
    };
    for (final e in wajibOnline.entries) {
      final isi = File('lib/screens/${e.key}').readAsStringSync();
      // Dicari TITIK PEMANGGILANNYA, bukan nama aksinya: nama aksi sering muncul
      // lebih dulu di komentar dokumentasi kepala berkas, dan jendela di
      // sekitarnya tidak ada hubungannya dengan keputusan ini.
      final i = isi.indexOf("aksi('${e.value}'");
      expect(i, greaterThan(0), reason: 'pemanggilan ${e.value} tidak ditemukan');
      final sebelum = isi.substring((i - 700).clamp(0, i), i);
      expect(sebelum, contains('ONLINE-ONLY'),
          reason: '${e.value} dibaca langsung tanpa alasan tertulis');
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
      // Pratinjau & komit berpasangan: server yang memilih baris mana dihapus.
      'kode_akun_screen.dart': "kode_akun_bersihkan', {})",
      // Pengaturan GLOBAL lintas perangkat.
      'konfigurasi_screen.dart': 'pengaturan_edit_transaksi_global_simpan',
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
