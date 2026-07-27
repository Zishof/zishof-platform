/// Model data POS pilot -- bentuknya mengikuti persis kontrak JSON Api_eBisnis
/// (identik PosApi.java, lihat prosesKatalog/prosesKonfigurasi di server).
class Produk {
  final int id;
  final String kode;
  final String barcode;
  final String nama;
  final double hargaJual;
  final int stok;
  final int? kategoriId;
  final String kategoriNama;
  final String? gambarUrl;

  Produk({
    required this.id,
    required this.kode,
    required this.barcode,
    required this.nama,
    required this.hargaJual,
    required this.stok,
    required this.kategoriId,
    required this.kategoriNama,
    required this.gambarUrl,
  });

  factory Produk.fromJson(Map<String, dynamic> j) => Produk(
        id: j['id'] as int,
        kode: (j['kode'] ?? '') as String,
        barcode: (j['barcode'] ?? '') as String,
        nama: (j['nama'] ?? '') as String,
        hargaJual: (j['hargaJual'] as num?)?.toDouble() ?? 0,
        stok: (j['stok'] as num?)?.toInt() ?? 0,
        kategoriId: j['kategoriId'] as int?,
        kategoriNama: (j['kategoriNama'] ?? '') as String,
        gambarUrl: j['gambarUrl'] as String?,
      );
}

class Kategori {
  final int id;
  final String nama;
  Kategori({required this.id, required this.nama});
  factory Kategori.fromJson(Map<String, dynamic> j) =>
      Kategori(id: j['id'] as int, nama: (j['nama'] ?? '') as String);
}

class CaraBayar {
  final int id;
  final String nama;
  final bool manual;
  CaraBayar({required this.id, required this.nama, required this.manual});
  factory CaraBayar.fromJson(Map<String, dynamic> j) => CaraBayar(
        id: j['id'] as int,
        nama: (j['nama'] ?? '') as String,
        manual: j['manual'] == true,
      );
}

/// Satu baris di keranjang -- disalin dari [Produk] + jumlah yang dipilih kasir.
/// [diskon]/[cashback]/[aturanDiskonId] diisi hasil `diskon_evaluasi` (lihat
/// KeranjangScreen._evaluasiDiskon) -- default 0/null sebelum evaluasi pertama.
class ItemKeranjang {
  final Produk produk;
  int jumlah;
  double diskon;
  double cashback;
  int? aturanDiskonId;
  ItemKeranjang({required this.produk, this.jumlah = 1, this.diskon = 0, this.cashback = 0, this.aturanDiskonId});
  double get subtotal => produk.hargaJual * jumlah;
  double get subtotalSetelahDiskon => subtotal - diskon;
}

/// Anggota/member koperasi -- bentuk JSON mengikuti `jsonMember` di PosApi.java
/// (dipakai aksi `cari_member`).
class Anggota {
  final int id;
  final String nama;
  final String kodeIdentitas;
  final bool wajibPin;
  final double minSaldo;

  Anggota({
    required this.id,
    required this.nama,
    required this.kodeIdentitas,
    required this.wajibPin,
    required this.minSaldo,
  });

  factory Anggota.fromJson(Map<String, dynamic> j) => Anggota(
        id: j['id'] as int,
        nama: (j['nama'] ?? '') as String,
        kodeIdentitas: (j['kodeIdentitas'] ?? '') as String,
        wajibPin: j['wajibPin'] == true,
        minSaldo: (j['minSaldo'] as num?)?.toDouble() ?? 0,
      );

  /// Dari baris cache lokal (anggota_cache, kolom snake_case SQLite) -- dipakai
  /// picker member saat offline, lihat CoreDb.cariAnggotaCache.
  factory Anggota.fromCache(Map<String, Object?> b) => Anggota(
        id: b['id'] as int,
        nama: (b['nama'] ?? '') as String,
        kodeIdentitas: (b['kode_identitas'] ?? '') as String,
        wajibPin: (b['wajib_pin'] as int? ?? 0) == 1,
        minSaldo: 0,
      );
}
