class AppVariant {
  AppVariant._();

  static const kode = String.fromEnvironment(
    'EBISNIS_VARIANT',
    defaultValue: 'default',
  );

  static const isAlBahjah = kode == 'albahjah';

  /// Varian "eBisnis Inventory & Sales" (48 layar legacy + Nota Sales -- lihat
  /// docs/pos-inventory-sales). Build WAJIB memakai KEDUANYA:
  /// `-t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales`
  /// (dart-define menggerakkan konstanta compile-time ini + deteksi variant.cmake
  /// Windows; entrypoint menggerakkan AppProductProfile runtime).
  static const isInventorySales = kode == 'inventory_sales';

  /// Varian "POS Apotik" (eFarmasi) -- penjualan obat resep/bebas dgn batch-
  /// kedaluwarsa & obat terkendali; backend Java AIS + modul SIRS (JALAN 1).
  /// Build: `-t lib/main_apotik.dart --dart-define=EBISNIS_VARIANT=apotik`.
  static const isApotik = kode == 'apotik';

  static const isEBisnis = kode == 'default' || kode == 'ebisnis';

  static const namaAplikasi = isAlBahjah
      ? 'Al-Bahjah POS'
      : (isInventorySales
          ? 'eBisnis Inventory & Sales'
          : (isApotik ? 'eBisnis POS Apotik' : 'eBisnis'));
  static const namaSidebar = isAlBahjah
      ? 'Al-Bahjah POS'
      : (isInventorySales
          ? 'Inventory & Sales'
          : (isApotik ? 'POS Apotik' : 'eBisnis POS'));
  static const updateAssetKeyword = isAlBahjah
      ? 'albahjah'
      : (isInventorySales ? 'inventorysales' : (isApotik ? 'apotik' : 'ebisnis'));
  static const labelPerangkat = isAlBahjah
      ? 'Al-Bahjah POS Flutter Pilot'
      : (isInventorySales
          ? 'eBisnis Inventory & Sales Flutter'
          : (isApotik ? 'eBisnis POS Apotik Flutter' : 'eBisnis Flutter Pilot'));
  static const logoAsset = isAlBahjah
      ? 'assets/images/albahjah/icon.png'
      : (isInventorySales
          ? 'assets/images/inventory_sales/icon.png'
          : (isApotik
              ? 'assets/images/apotik/icon.png'
              : 'assets/images/ebisnis/icon.png'));
}
