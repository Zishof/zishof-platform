class AppVariant {
  AppVariant._();

  static const kode = String.fromEnvironment(
    'EBISNIS_VARIANT',
    defaultValue: 'default',
  );

  static const isAlBahjah = kode == 'albahjah';

  /// Varian POS Al-Bahjah An-Nahl. Server bawaan berada pada
  /// https://an-nahl.santri.info/nahl dan namespace lokalnya dipisahkan dari
  /// Al-Bahjah umum agar transaksi, cache, serta outbox tidak bercampur.
  static const isNahl = kode == 'nahl';

  /// Varian "eBisnis Inventory & Sales" (48 layar legacy + Nota Sales -- lihat
  /// docs/pos-inventory-sales). Build WAJIB memakai KEDUANYA:
  /// `-t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales`
  /// (dart-define menggerakkan konstanta compile-time ini + deteksi variant.cmake
  /// Windows; entrypoint menggerakkan AppProductProfile runtime).
  static const isInventorySales = kode == 'inventory_sales';

  /// Varian demo/produksi AB Chicken. Fitur operasionalnya diturunkan dari
  /// Inventory & Sales, tetapi namespace lokal, branding, server bawaan, dan
  /// artefak rilis dipisahkan total. Ejaan domain/schema produksi memang
  /// `abchiken`, sedangkan kode varian/brand tetap `abchicken`.
  /// Build: `-t lib/main_abchicken.dart --dart-define=EBISNIS_VARIANT=abchicken`.
  static const isAbChicken = kode == 'abchicken';

  /// Varian "POS Apotik" (eFarmasi) -- penjualan obat resep/bebas dgn batch-
  /// kedaluwarsa & obat terkendali; backend Java AIS + modul SIRS (JALAN 1).
  /// Build: `-t lib/main_apotik.dart --dart-define=EBISNIS_VARIANT=apotik`.
  static const isApotik = kode == 'apotik';

  /// Varian "POS eMedik" -- kasir layanan medis; SUDAH TERMASUK seluruh fitur
  /// POS Apotik dalam satu build (perbedaan hak diatur Tbmrole di server,
  /// bukan binary terpisah). Server bawaan: dev.ecampus.id/ecampus.
  /// Build: `-t lib/main_emedik.dart --dart-define=EBISNIS_VARIANT=emedik`.
  static const isEmedik = kode == 'emedik';

  /// Varian "MitraInap" -- admin hotel/penginapan (backend Java AIS, aksi
  /// hotel_* / HotelApiHelper). Aset ikon & latar login masih menumpang
  /// ebisnis (belum ada aset khusus -- menunjuk aset yang tidak ada = crash
  /// load gambar), tapi storage/update keyword WAJIB terpisah supaya data
  /// lokal tidak tercampur dan updater tidak menarik APK/installer ebisnis.
  /// Build: `-t lib/main_mitrainap.dart --dart-define=EBISNIS_VARIANT=mitrainap`.
  static const isMitraInap = kode == 'mitrainap';

  /// Varian "eKantin Petra" -- kantin Universitas Kristen Petra, dikelola
  /// Direktorat Pengembangan Usaha Sosial. Server bawaan
  /// kantinpcu.ecampus.id/petra (lihat AppSetting.baseUrlHost). Layar Masuk
  /// memakai tata letak dua kolom mengikuti versi web-nya.
  /// Build: `-t lib/main_petra.dart --dart-define=EBISNIS_VARIANT=petra`.
  static const isPetra = kode == 'petra';

  static const isEBisnis = kode == 'default' || kode == 'ebisnis';

  /// Namespace stabil untuk seluruh data lokal. Nilai ini tidak mengikuti
  /// nama tampilan sehingga perubahan branding tidak pernah mencampur DB,
  /// backup transaksi, atau konfigurasi antar aplikasi yang dipasang pada
  /// komputer/perangkat yang sama.
  static const storageNamespace = isAbChicken
      ? 'abchicken'
      : (isAlBahjah
          ? 'albahjah'
          : (isNahl
              ? 'nahl'
              : (isInventorySales
                  ? 'inventory_sales'
                  : (isApotik
                      ? 'apotik'
                      : (isEmedik
                          ? 'emedik'
                          : (isMitraInap
                              ? 'mitrainap'
                              : (isPetra ? 'petra' : 'ebisnis')))))));

  static const namaAplikasi = isAbChicken
      ? 'AB Chicken'
      : (isAlBahjah
          ? 'Al-Bahjah POS'
          : (isNahl
              ? 'TokoQu Al-Bahjah An Nahl'
              : (isInventorySales
                  ? 'eBisnis Inventory & Sales'
                  : (isApotik
                      ? 'eBisnis POS Apotik'
                      : (isEmedik
                          ? 'eBisnis POS eMedik'
                          : (isMitraInap
                              ? 'MitraInap'
                              : (isPetra ? 'eKantin Petra' : 'eBisnis')))))));
  static const namaSidebar = isAbChicken
      ? 'AB Chicken Operations'
      : (isAlBahjah
          ? 'Al-Bahjah POS'
          : (isNahl
              ? 'TokoQu An Nahl'
              : (isInventorySales
                  ? 'Inventory & Sales'
                  : (isApotik
                      ? 'POS Apotik'
                      : (isEmedik
                          ? 'POS eMedik'
                          : (isMitraInap
                              ? 'MitraInap'
                              : (isPetra
                                  ? 'eKantin Petra'
                                  : 'eBisnis POS')))))));
  static const updateAssetKeyword = isAbChicken
      ? 'abchicken'
      : (isAlBahjah
          ? 'albahjah'
          : (isNahl
              ? 'nahl'
              : (isInventorySales
                  ? 'inventorysales'
                  : (isApotik
                      ? 'apotik'
                      : (isEmedik
                          ? 'emedik'
                          : (isMitraInap
                              ? 'mitrainap'
                              : (isPetra ? 'petra' : 'ebisnis')))))));

  /// Setiap produk menggunakan tag rilis sendiri. Pemisahan ini mencegah
  /// paket AB Chicken, Al-Bahjah, Nahl, atau produk lain ditawarkan silang
  /// oleh pemeriksa pembaruan otomatis.
  static const String? updateTagPrefix = isAbChicken
      ? 'abchicken-'
      : (isAlBahjah
          ? 'albahjah-'
          : (isNahl
              ? 'nahl-'
              : (isApotik
                  ? 'apotik-'
                  : (isEmedik
                      ? 'emedik-'
                      : (isMitraInap
                          ? 'mitrainap-'
                          : (isPetra ? 'petra-' : null))))));
  static const labelPerangkat = isAbChicken
      ? 'AB Chicken POS & Operations'
      : (isAlBahjah
          ? 'Al-Bahjah POS Flutter Pilot'
          : (isNahl
              ? 'TokoQu Al-Bahjah An Nahl Flutter'
              : (isInventorySales
                  ? 'eBisnis Inventory & Sales Flutter'
                  : (isApotik
                      ? 'eBisnis POS Apotik Flutter'
                      : (isEmedik
                          ? 'eBisnis POS eMedik Flutter'
                          : (isMitraInap
                              ? 'MitraInap Flutter'
                              : (isPetra
                                  ? 'eKantin Petra Flutter'
                                  : 'eBisnis Flutter Pilot')))))));
  static const logoAsset = isAbChicken
      ? 'assets/images/abchicken/icon.png'
      : (isAlBahjah
          ? 'assets/images/albahjah/icon.png'
          : (isNahl
              ? 'assets/images/nahl/icon.png'
              : (isInventorySales
                  ? 'assets/images/inventory_sales/icon.png'
                  : (isApotik
                      ? 'assets/images/apotik/icon.png'
                      : (isEmedik
                          ? 'assets/images/emedik/icon.png'
                          : (isPetra
                              ? 'assets/images/petra/icon.png'
                              : 'assets/images/ebisnis/icon.png'))))));

  /// Latar layar masuk mengikuti unit usaha. Aset sengaja dipisah per varian
  /// agar identitas eBisnis umum, Inventory, Apotik, eMedik, dan Al-Bahjah
  /// tetap konsisten pada build Desktop maupun Android.
  static const loginBackgroundAsset = isAbChicken
      ? 'assets/images/abchicken/login-background.png'
      : (isAlBahjah
          ? 'assets/images/albahjah/login-background.png'
          : (isNahl
              ? 'assets/images/nahl/login-background.jpg'
              : (isInventorySales
                  ? 'assets/images/inventory_sales/login-background.png'
                  : (isApotik
                      ? 'assets/images/apotik/login-background.png'
                      : (isEmedik
                          ? 'assets/images/emedik/login-background.png'
                          : (isPetra
                              ? 'assets/images/petra/login-background.png'
                              : 'assets/images/ebisnis/login-background.png'))))));

  /// Judul kartu di layar Masuk -- BEDA dari [namaAplikasi] (yang tetap dipakai
  /// di window title/sidebar/label perangkat/update asset keyword). Al-Bahjah
  /// minta identitas unit usaha ("Unit Usaha Al Bahjah"), bukan nama produk
  /// "Al-Bahjah POS", HANYA di kartu login.
  static const judulLogin = isAbChicken
      ? 'AB Chicken Operations'
      : (isAlBahjah
          ? 'Unit Usaha Al Bahjah'
          : (isNahl
              ? 'TokoQu Al-Bahjah An Nahl'
              : (isPetra ? 'Masuk eKantin' : namaAplikasi)));

  /// Sub-judul (tagline) di bawah judul kartu Masuk. Al-Bahjah minta kalimat
  /// visi-misi pesantren menggantikan "Masuk sebagai Kasir" generik.
  static const subJudulLogin = isAbChicken
      ? 'Satu alur untuk outlet, gudang pusat, produksi, pengiriman, dan keuangan'
      : (isAlBahjah
          ? 'Membangun Masyarakat Berahlaq Mulia, Bersendikan Al-Qur’an dan Sunnah Rasulullah SAW'
          : (isNahl
              ? 'Menyiapkan generasi Qur’ani yang berakhlakul karimah dan berwawasan global'
              : (isInventorySales
                  ? 'Kelola persediaan, penjualan, dan operasional usaha'
                  : (isApotik
                      ? 'Masuk sesuai peran Anda di layanan Apotik'
                      : (isEmedik
                          ? 'Masuk sesuai peran Anda di layanan eMedik'
                          : (isPetra
                              ? 'Selamat datang kembali, silakan masuk ke akun Anda.'
                              : 'Masuk ke sistem operasional eBisnis'))))));

  /// ── Identitas panel kiri layar Masuk (khusus Petra) ────────────────────
  /// Versi web eKantin Petra memakai kartu dua kolom: panel biru berisi
  /// identitas unit + kontak, dan panel putih berisi formulir. Nilai di bawah
  /// mengisi panel kiri tersebut; varian lain tidak memakainya.
  static const namaOrganisasiLogin =
      isPetra ? 'Direktorat Pengembangan Usaha Sosial' : namaAplikasi;
  static const alamatKontakLogin = isPetra
      ? 'Gedung Entrance Hall (EH), Lantai 2. UNIVERSITAS KRISTEN PETRA'
      : '';
  static const teleponKontakLogin = isPetra ? '+62-881-2526-094' : '';
  static const emailKontakLogin = isPetra ? 'office-dpus@petra.ac.id' : '';
  static const hakCiptaLogin =
      isPetra ? '© 2026 Direktorat Pengembangan Usaha Sosial' : '';

  /// Tata letak Masuk dua kolom (panel identitas + formulir). Sementara hanya
  /// Petra yang memakainya; varian lain tetap kartu tunggal spt sebelumnya.
  static const loginDuaKolom = isPetra;
}
