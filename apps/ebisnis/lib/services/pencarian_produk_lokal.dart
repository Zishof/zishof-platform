import 'package:core_db/core_db.dart';

/// Cari produk secara PERSIS dari cache katalog perangkat.
///
/// Ini adalah pagar kedua ketika server lama belum mengenali kolom barcode
/// fisik atau koneksi terputus. Pencocokan sengaja tidak memakai `contains`:
/// satu digit yang mirip tidak boleh mengarahkan penerimaan ke produk lain.
Future<Map<String, dynamic>?> cariProdukLokalPersis(String kode) async {
  final dicari = kode.trim().toLowerCase();
  if (dicari.isEmpty) return null;
  final kandidat = await CoreDb.instance.produkCache(
    keyword: dicari,
    limit: 50,
  );
  final cocok = produkCacheCocokPersis(kandidat, dicari);
  if (cocok == null) return null;
  return bentukProdukKulakanDariCache(cocok);
}

/// Fungsi murni agar aturan kecocokan barcode/kode dapat diuji tanpa SQLite.
Map<String, Object?>? produkCacheCocokPersis(
  Iterable<Map<String, Object?>> kandidat,
  String kode,
) {
  final dicari = kode.trim().toLowerCase();
  if (dicari.isEmpty) return null;
  for (final produk in kandidat) {
    final kodeProduk = '${produk['kode'] ?? ''}'.trim().toLowerCase();
    final barcode = '${produk['barcode'] ?? ''}'.trim().toLowerCase();
    if (kodeProduk == dicari || barcode == dicari) return produk;
  }
  return null;
}

/// Bentuk kompatibel dengan respons `so_produk_scan` yang dipakai layar
/// Kulakan. Cache produk belum menyimpan harga beli/UOM pembelian, sehingga
/// nilai itu tidak ditebak; operator tetap mengisi harga sesuai faktur.
Map<String, dynamic> bentukProdukKulakanDariCache(
  Map<String, Object?> produk,
) =>
    <String, dynamic>{
      'produkId': (produk['id'] as num?)?.toInt(),
      'id': (produk['id'] as num?)?.toInt(),
      'kode': '${produk['kode'] ?? ''}',
      'barcode': '${produk['barcode'] ?? ''}',
      'nama': '${produk['nama'] ?? ''}',
      'stokSistem': (produk['stok'] as num?) ?? 0,
      'hargaJual': (produk['harga_jual'] as num?) ?? 0,
      'kategoriId': (produk['kategori_id'] as num?)?.toInt(),
      'kategoriNama': '${produk['kategori_nama'] ?? ''}',
      'faktorPembelianKeDasar': 1,
      'sumberCacheLokal': true,
    };
