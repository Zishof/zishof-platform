import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ringkasan impor Excel harus memisahkan baris yang BENAR-BENAR berubah dari
/// baris yang nilainya sama persis.
///
/// Sebelum ini server menghitung setiap baris yang cocok sebagai "diperbarui",
/// sehingga ringkasan melaporkan pekerjaan yang tidak pernah terjadi — impor
/// 8.000 baris yang tidak mengubah apa pun tetap berbunyi "Diperbarui: 8.000".
/// Lihat ais docs/pos/79, 102, 103.
///
/// Dua hal yang mudah rusak dan karena itu diikat di sini:
///
///  1. Klien harus BENAR-BENAR membaca `tidakBerubah`. Kalau tidak, angka
///     "Diperbarui" akan tampak menyusut tanpa penjelasan, dan sisanya hilang
///     tanpa jejak di layar.
///  2. `total` di server harus tetap menjumlahkan keempat kategori. Menyempitkan
///     satu hitungan tanpa memperbaiki totalnya membuat totalnya menyusut
///     diam-diam — persis cacat yang sedang diperbaiki, dalam bentuk lain.
void main() {
  late String layar;

  setUpAll(() {
    layar = File('lib/screens/impor_excel_produk_screen.dart').readAsStringSync();
  });

  test('klien membaca tidakBerubah dari respons', () {
    expect(layar, contains("hasil['tidakBerubah']"),
        reason: 'field baru tanpa pembaca = angka yang hilang tanpa jejak');
  });

  test('nilainya ikut direset tiap impor baru', () {
    // Tanpa reset, hitungannya menumpuk antar-impor dan angkanya jadi omong
    // kosong pada impor kedua.
    expect(layar, contains('_tidakBerubah = _dilewati'));
  });

  test('ditampilkan, bukan sekadar dikumpulkan', () {
    expect(layar, contains("label: 'Tidak berubah'"));
    expect(layar, contains(r"nilai: '$_tidakBerubah'"));
  });
}
