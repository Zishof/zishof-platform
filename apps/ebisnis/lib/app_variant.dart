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

  static const isEBisnis = kode == 'default' || kode == 'ebisnis';

  static const namaAplikasi = isAlBahjah
      ? 'Al-Bahjah POS'
      : (isInventorySales ? 'eBisnis Inventory & Sales' : 'eBisnis');
  static const namaSidebar = isAlBahjah
      ? 'Al-Bahjah POS'
      : (isInventorySales ? 'Inventory & Sales' : 'eBisnis POS');
  static const updateAssetKeyword =
      isAlBahjah ? 'albahjah' : (isInventorySales ? 'inventorysales' : 'ebisnis');
  static const labelPerangkat = isAlBahjah
      ? 'Al-Bahjah POS Flutter Pilot'
      : (isInventorySales
          ? 'eBisnis Inventory & Sales Flutter'
          : 'eBisnis Flutter Pilot');
  static const logoAsset = isAlBahjah
      ? 'assets/images/albahjah/icon.png'
      : (isInventorySales
          ? 'assets/images/inventory_sales/icon.png'
          : 'assets/images/ebisnis/icon.png');
}
