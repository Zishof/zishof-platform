class AppVariant {
  AppVariant._();

  static const kode = String.fromEnvironment(
    'EBISNIS_VARIANT',
    defaultValue: 'default',
  );

  static const isAlBahjah = kode == 'albahjah';
  static const isEBisnis = kode == 'default' || kode == 'ebisnis';

  static const namaAplikasi = isAlBahjah ? 'Al-Bahjah POS' : 'eBisnis';
  static const namaSidebar = isAlBahjah ? 'Al-Bahjah POS' : 'eBisnis POS';
  static const updateAssetKeyword = isAlBahjah ? 'albahjah' : 'ebisnis';
  static const labelPerangkat =
      isAlBahjah ? 'Al-Bahjah POS Flutter Pilot' : 'eBisnis Flutter Pilot';
  static const logoAsset = isAlBahjah
      ? 'assets/images/albahjah/icon.png'
      : 'assets/images/ebisnis/icon.png';
}
