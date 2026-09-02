import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga: FORMULIR modul local-first harus dapat DIISI offline, bukan hanya
/// disimpan offline.
///
/// Produk, Kulakan, dan Grup Produk sudah lama menyimpan lewat antrean, jadi
/// tampak aman tanpa sinyal. Tetapi dropdown referensinya — satuan/UOM,
/// pemasok, grup produk, promo — mengambil langsung ke jaringan dan jatuh
/// menjadi daftar KOSONG. Formulirnya tetap terbuka dan tetap bisa disimpan;
/// yang hilang justru isinya. Itu bentuk local-first terbalik: tulisannya
/// diselamatkan, bacaan yang menentukan isi tulisan itu tidak.
///
/// Kegagalannya SENYAP. Tidak ada galat — hanya pilihan yang tidak ada, lalu
/// dokumen tersimpan tanpa pemasok atau tanpa satuan yang dimaksud.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

String _isi(String jalur) => File(jalur).readAsStringSync();

void main() {
  const dropdown = <String, List<String>>{
    // aksi -> berkas yang memuatnya
    'uom_list': [
      'lib/screens/keranjang_screen.dart',
      'lib/screens/produk_screen.dart',
    ],
    'grup_produk_list': ['lib/screens/produk_screen.dart'],
    'diskon_list': ['lib/screens/grup_produk_screen.dart'],
    'penyedia_list': [
      'lib/screens/kulakan_screen.dart',
      'lib/screens/kulakan_bulk_entry_screen.dart',
    ],
  };

  test('dropdown referensi dimuat lewat MasterOffline', () {
    // Mencari `daftarDenganCache(` saja TIDAK cukup: berkas-berkas ini sudah
    // memakai MasterOffline untuk daftar lain, jadi penjaga selonggar itu tetap
    // hijau walau justru aksi inilah yang dikembalikan ke jalur langsung.
    // Karena itu nama aksinya diikat pada pemanggilannya.
    for (final e in dropdown.entries) {
      for (final berkas in e.value) {
        final padat = _rapat(_isi(berkas));
        expect(padat, contains(_rapat("daftarDenganCache('${e.key}'")),
            reason: '$berkas memuat ${e.key} di luar jalur cache');
      }
    }
  });

  test('jalur langsung ke server sudah benar-benar ditinggalkan', () {
    // Pengecualian tunggal: `penyedia_list` MEMPERTAHANKAN panggilan langsung
    // untuk cabang pencariannya — diuji tersendiri di bawah.
    const bekas = <String, List<String>>{
      'uom_list': [
        'lib/screens/keranjang_screen.dart',
        'lib/screens/produk_screen.dart',
      ],
      'grup_produk_list': ['lib/screens/produk_screen.dart'],
      'diskon_list': ['lib/screens/grup_produk_screen.dart'],
    };
    for (final e in bekas.entries) {
      for (final berkas in e.value) {
        expect(_rapat(_isi(berkas)),
            isNot(contains(_rapat("ApiClient.instance.aksi('${e.key}'"))),
            reason: '$berkas masih punya jalur langsung ke ${e.key}');
      }
    }
  });

  test('UOM keranjang dan UOM produk TIDAK berbagi kunci cache', () {
    // Layar Produk meminta satuan NONAKTIF juga (supaya produk lama masih bisa
    // disunting); keranjang hanya yang aktif. Satu kunci untuk dua konteks
    // membuat kasir ditawari satuan mati sebagai pilihan jual — tanpa tanda apa
    // pun, karena keduanya sama-sama "berhasil".
    final keranjang = _rapat(_isi('lib/screens/keranjang_screen.dart'));
    final produk = _rapat(_isi('lib/screens/produk_screen.dart'));
    expect(keranjang, contains(_rapat("'master:uom:aktif'")));
    expect(produk, contains(_rapat("'master:uom:termasuk_nonaktif'")));
    expect(keranjang, isNot(contains(_rapat("'master:uom:termasuk_nonaktif'"))),
        reason: 'keranjang tidak boleh menyajikan satuan nonaktif');
  });

  test('hanya daftar AWAL pemasok yang di-cache, bukan hasil pencarian', () {
    // Menyimpan hasil pencarian per kata kunci menumpuk snapshot yang tak
    // pernah terpakai lagi, dan menyajikannya kembali membuat kata kunci yang
    // BERBEDA tampak cocok.
    for (final berkas in const [
      'lib/screens/kulakan_screen.dart',
      'lib/screens/kulakan_bulk_entry_screen.dart',
    ]) {
      final padat = _rapat(_isi(berkas));
      expect(padat, contains(_rapat('keyword.isEmpty')),
          reason: '$berkas menyamakan pencarian dengan daftar awal');
      expect(padat, contains(_rapat("'master:penyedia:awal'")));
      // Jalur pencarian harus TETAP langsung ke server.
      expect(padat, contains(_rapat("aksi('penyedia_list',{'keyword':keyword})")),
          reason: '$berkas kehilangan jalur pencarian daringnya');
    }
  });

  test('filter toko punya snapshot, tetapi wewenangnya tidak ikut dipulihkan',
      () {
    // Daftar tokonya boleh datang dari snapshot; wewenangnya tidak. Menaikkan
    // `bolehSemuaToko` dari cache menghidupkan lingkup "semua toko" bagi
    // pengguna yang wewenangnya sudah dicabut — justru pada saat server tidak
    // berada di jalur untuk menolaknya.
    final isi = _isi('lib/widgets/app_shell.dart');
    final padat = _rapat(isi);
    expect(padat, contains(_rapat("_kunciCacheTokoFilter = 'master:toko_filter'")));
    expect(padat, contains(_rapat('ambilCacheReferensi(_kunciCacheTokoFilter)')),
        reason: 'snapshot filter toko tidak pernah dibaca kembali');

    // `bolehSemuaToko` juga DIBACA di beberapa tempat untuk merender pemilih
    // lingkup; yang dijaga di sini khusus PENYETELANNYA. Mencocokkan namanya
    // saja akan menghitung pembacaan itu juga.
    final setel = RegExp(r'Sesi\.instance\.bolehSemuaToko\s*=');
    expect(setel.allMatches(isi).length, 1,
        reason: 'wewenang lingkup toko disetel di lebih dari satu jalur');

    // Penyetelan itu harus berada di jalur DARING, yakni sebelum blok pemulihan
    // snapshot dimulai.
    final awal = isi.indexOf('Future<void> muatDaftarTokoFilter()');
    expect(awal, greaterThan(0), reason: 'pemuat filter toko tidak ditemukan');
    final fungsi = isi.substring(awal, isi.indexOf('\n}', awal));
    expect(setel.firstMatch(fungsi)!.start,
        lessThan(fungsi.indexOf('ambilCacheReferensi')),
        reason: 'wewenang lingkup toko ikut dipulihkan dari snapshot');
  });

  test('kerangka aplikasi tidak menyalakan antrean tulis hanya untuk membaca',
      () {
    // MasterOffline memasang timer flush outbox begitu dipanggil. Memuat
    // dropdown filter toko adalah pembacaan murni milik kerangka aplikasi;
    // menariknya lewat MasterOffline menyalakan antrean mutasi master sebagai
    // efek samping — terlihat pertama kali sebagai timer yang menggantung dan
    // menjatuhkan empat uji widget yang tidak berhubungan.
    expect(_isi('lib/widgets/app_shell.dart'),
        isNot(contains('master_offline.dart')),
        reason: 'app_shell menarik MasterOffline hanya untuk membaca');
  });
}
