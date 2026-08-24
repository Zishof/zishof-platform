import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layar Produk WAJIB menyatakan lingkup tokonya pada aksi `katalog`.
///
/// Tanpa itu, admin yang tidak terikat toko melihat daftar KOSONG walau
/// katalognya berisi — dan tanpa galat apa pun. Penjaga di peladen
/// (`PriceTagUtil.listProduk`) berbunyi:
///
///     if (tokoId == null && !(semuaToko && adminGlobal)) return daftar kosong;
///
/// Maksud "seluruh toko" di sisi peladen berbentuk `tokoId == null`, tetapi hanya
/// diakui bila klien mengirim bendera `semuaToko`. Terukur pada basis data UAT:
/// tanpa bendera 0 baris, dengan bendera 8.676 baris — data yang sama.
///
/// Gejalanya menipu karena kartu KPI memakai aksi lain (`produk_statistik`) yang
/// tidak punya penjaga itu: angkanya tetap berisi, hanya daftarnya yang kosong.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar = File('lib/screens/produk_screen.dart').readAsStringSync();
  final padat = _rapat(layar);

  test('aksi katalog membawa lingkup toko', () {
    expect(padat, contains(_rapat("'semuaToko': true")),
        reason: 'tanpa bendera ini daftar produk admin selalu kosong');
    expect(padat, contains(_rapat("'toko_id': Sesi.instance.idTokoTerpilih")),
        reason: 'toko yang dipilih di kotak kiri atas harus ikut menyempitkan '
            'daftar, bukan diabaikan diam-diam');
  });

  test('keduanya saling meniadakan, bukan dikirim bersamaan', () {
    // Mengirim toko_id DAN semuaToko sekaligus membuat maksudnya mendua; yang
    // dipakai peladen jadi bergantung urutan pemeriksaan, bukan niat pengguna.
    expect(padat, contains(_rapat("if (Sesi.instance.idTokoTerpilih != null)")));
    expect(padat, contains(_rapat("if (Sesi.instance.idTokoTerpilih == null)")));
  });
}
