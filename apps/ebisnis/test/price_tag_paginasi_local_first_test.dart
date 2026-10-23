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

  test('layar gagal memuat menyediakan retry tanpa menghapus pilihan barang',
      () {
    final awal = source.indexOf('Widget _tampilanGagalMuatProduk()');
    final akhir = source.indexOf('Widget _barCetak()', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));
    final tampilanGagal = source.substring(awal, akhir);
    expect(tampilanGagal, contains('Coba Muat Ulang Produk'));
    expect(tampilanGagal, contains('_panelOpsi()'));
    expect(tampilanGagal, contains('_barCetak()'));
    expect(tampilanGagal, contains('_idTerpilih.length'));
    expect(tampilanGagal, contains('_muatHalaman(resetHalaman: true)'));
    expect(tampilanGagal, isNot(contains('_idTerpilih.clear()')));
    expect(tampilanGagal, isNot(contains('_produkTerpilihMap.clear()')));
  });

  test('price tag tidak membaca seluruh cache katalog untuk metadata halaman', () {
    expect(source, isNot(contains('CoreDb.instance.produkCache()')));
    expect(source, isNot(contains('_lengkapiMetadataProduk(')));
  });
}
