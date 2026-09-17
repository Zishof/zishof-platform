import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rekap produk terjual harus memperlihatkan aritmetikanya: Bruto - Diskon = Total.
///
/// Keluhan produksi Al-Bahjah/An Nahl 17-09-2026:
///   "Roti bakar 7.000 x 4 = 28.000 tapi jadi 24.000"
///   "Mangga 7000 x 21.000 tapi totalnya 19.000"
///   "Harganya sudah bener tapi kenapa totalny salah"
///
/// Angkanya TIDAK salah. Server menyimpan `total = (harga * qty) - diskon`
/// (KantinHelper.java:1152), dan rekap per-produk menjumlahkan total NETO itu.
/// Yang hilang adalah diskonnya: tampilan per-transaksi punya kolom Diskon,
/// rekap per-produk tidak — jadi 28.000 - 4.000 = 24.000 tampak seperti salah
/// hitung. Selisih 6.000 terhadap rekap Excel kantin (4.000 + 2.000) adalah
/// jumlah diskon yang tidak pernah ditampilkan, bukan uang yang hilang.
///
/// Dua hal yang diikat di sini, karena dua-duanya mudah rusak lagi:
///
///  1. Diskon dan bruto harus DIKUMPULKAN per produk. Tanpa itu tidak ada yang
///     bisa ditampilkan.
///  2. Keduanya harus benar-benar MUNCUL sebagai kolom. Angka yang dikumpulkan
///     tapi tidak dibaca siapa pun adalah cacat yang sama persis dengan yang
///     sedang diperbaiki — lihat ais docs/pos/45, 46, 75, 80, 92, 96.
void main() {
  late String layar;

  setUpAll(() {
    layar =
        File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync();
  });

  test('diskon per produk dikumpulkan, bukan dibuang', () {
    expect(layar, contains("'diskonRekap'"),
        reason: 'tanpa ini selisih harga x qty vs total tidak punya penjelasan');
  });

  test('bruto per produk dikumpulkan', () {
    expect(layar, contains("'brutoRekap'"),
        reason: 'bruto = harga x qty, angka yang dihitung ulang kasir di Excel');
  });

  test('bruto dijumlahkan dari total + diskon, bukan dikira-kira', () {
    // total yang disimpan sudah NETO, jadi brutonya harus dipulihkan dengan
    // menambahkan kembali diskon baris itu. Mengalikan harga x qty di klien
    // akan meleset untuk baris berharga khusus.
    expect(layar, contains('totalBaris + diskonBaris'));
  });

  test('keduanya tampil sebagai kolom, bukan hanya dihitung', () {
    expect(layar, contains("DynamicReportColumn('brutoRekap'"),
        reason: 'dikumpulkan tanpa pembaca = keluhan yang sama muncul lagi');
    expect(layar, contains("DynamicReportColumn('diskonRekap'"));
  });
}
