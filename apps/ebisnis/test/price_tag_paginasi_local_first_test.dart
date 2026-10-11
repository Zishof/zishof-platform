import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/screens/price_tag_screen.dart').readAsStringSync();

  test('price tag membaca cache SQLite terbatas sebelum meminta server', () {
    final awal = source.indexOf('Future<void> _muatHalaman(');
    final akhir = source.indexOf('void _onCariChanged(', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));
    final pemuatan = source.substring(awal, akhir);
    expect(pemuatan, contains('produkCacheMaster('));
    expect(pemuatan, contains('limit: _itemPerHalaman'));
    expect(pemuatan, contains('offset: _halaman * _itemPerHalaman'));
    expect(
      pemuatan.indexOf('produkCacheMaster('),
      lessThan(
          pemuatan.indexOf("ApiClient.instance.aksi('price_tag_list_produk'")),
    );
  });

  test('refresh gagal tidak menghapus halaman lokal yang sudah tampil', () {
    expect(source, contains('Cache yang sudah tampil dipertahankan'));
    expect(source, contains('if (daftarLokal.isEmpty)'));
  });

  test('metadata price tag tidak meminta seluruh katalog tanpa pagination', () {
    final awal = source.indexOf('Future<void> _lengkapiMetadataProduk(');
    final akhir = source.indexOf('void _gabungMetadataProduk(', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));
    expect(source.substring(awal, akhir), isNot(contains("aksi('katalog'")));
  });
}
