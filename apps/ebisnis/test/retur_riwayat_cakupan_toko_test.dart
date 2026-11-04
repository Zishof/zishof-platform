import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mengunci agar daftar dan perubahan retur memakai lingkup toko yang sama.
/// Daftar tetap lewat MasterOffline supaya salinan lokal tampil lebih dahulu.
void main() {
  test('riwayat retur penjualan mengirim dan memakai lingkup toko aktif', () {
    final source =
        File('lib/screens/retur_penjualan_screen.dart').readAsStringSync();
    final padat = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(padat, contains("daftarCacheDulu( 'retur_penjualan_list'"));
    expect(padat, contains("if (idToko != null) 'toko_id': idToko"));
    expect(padat, contains('master:retur_penjualan:'));
    expect(padat, contains('idToko ??'));
    expect(padat, contains('semua'));
    expect(
      RegExp(r"cacheKey:\s*'master:retur_penjualan:\$\{Sesi\.instance\.idTokoTerpilih")
          .allMatches(padat)
          .length,
      3,
      reason: 'tambah, ubah, dan hapus harus menyegarkan daftar toko aktif',
    );
  });

  test('riwayat retur pembelian mengirim dan memakai lingkup toko aktif', () {
    final source =
        File('lib/screens/retur_pembelian_screen.dart').readAsStringSync();
    final padat = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(padat, contains("daftarCacheDulu( 'retur_pembelian_list'"));
    expect(padat, contains("if (idToko != null) 'toko_id': idToko"));
    expect(padat, contains('master:retur_pembelian:'));
    expect(padat, contains('idToko ??'));
    expect(padat, contains('semua'));
    expect(
      RegExp(r"cacheKey:\s*'master:retur_pembelian:\$\{Sesi\.instance\.idTokoTerpilih")
          .allMatches(padat)
          .length,
      2,
      reason: 'simpan dan hapus harus menyegarkan daftar toko aktif',
    );
  });
}
