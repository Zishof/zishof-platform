import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/models.dart';

void main() {
  test('cache mempertahankan modal, resep, UOM dan kebijakan saat offline', () {
    final source = <String, dynamic>{
      'id': 7, 'nama': 'Produk uji', 'kode': 'UJI-7',
      'hargaBeli': 4850, 'hargaJual': 7000, 'stok': 45,
      'satuanId': 4, 'satuanNama': 'Pcs', 'satuanPembelianId': 5,
      'satuanPembelianNama': 'Dus', 'hargaBeliManual': true,
      'bahanBaku': [{'produkId': 8, 'qty': 2, 'harga': 2425}],
      'keterangan': 'Catatan uji', 'rute': 'PRODUKSI', 'perluQc': true,
      'kebijakanReturId': 3, 'kebijakanReturNama': 'Uji retur',
    };
    final row = Produk.baseKeCacheRow(source);
    final restored = Produk.fromJson(Produk.cacheRowKeJson(row));
    expect(restored.hargaBeli, 4850);
    expect(restored.hargaJual, 7000);
    expect(restored.stok, 45);
    expect(restored.bahanBaku, source['bahanBaku']);
    expect(restored.satuanPembelianId, 5);
    expect(restored.hargaBeliManual, isTrue);
    expect(restored.keterangan, 'Catatan uji');
    expect(restored.kebijakanReturId, 3);
    expect(restored.detailTersedia, isTrue);
    // Stok ledger paling baru harus mengalahkan snapshot detail lama.
    row['stok'] = 42;
    expect(Produk.fromJson(Produk.cacheRowKeJson(row)).stok, 42);
  });
  test('resep dari outbox mempertahankan id bahan snake case', () {
    final row = Produk.baseKeCacheRow({'id': 7, 'hargaBeli': 4850,
      'bahanBaku': [{'produk_id': 8, 'qty': 2, 'harga': 2425}]});
    final product = Produk.fromJson(Produk.cacheRowKeJson(row));
    expect(product.bahanBaku.single['produkId'], 8);
  });
  test('cache lama atau rusak dikenali sebagai detail belum lengkap', () {
    for (final detail in [null, '{rusak']) {
      final product = Produk.fromJson(Produk.cacheRowKeJson({
        'id': 7, 'harga_jual': 7000, 'stok': 45, 'detail_json': detail,
      }));
      expect(product.detailTersedia, isFalse);
      expect(product.hargaJual, 7000);
      expect(product.stok, 45);
    }
    expect(Produk.fromJson({'id': 7, 'hargaBeli': 0}).detailTersedia, isTrue);
  });
}
