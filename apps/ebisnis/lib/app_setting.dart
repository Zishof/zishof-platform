import 'package:flutter/material.dart';

import 'app_variant.dart';

/// Pilihan warna tema aplikasi -- dipilih pengguna sendiri lewat menu
/// Konfigurasi > Identitas Mesin > Tampilan (lihat
/// `AppThemeController.ubahWarna` di theme/app_theme.dart), TAPI nilai AWAL
/// (sebelum pengguna pernah mengubahnya) datang dari [AppSetting.temaBawaan]
/// per varian build.
enum AppThemeWarna { biru, merah, hijau, abuAbu }

extension AppThemeWarnaX on AppThemeWarna {
  String get label => switch (this) {
        AppThemeWarna.biru => 'Biru',
        AppThemeWarna.merah => 'Merah',
        AppThemeWarna.hijau => 'Hijau',
        AppThemeWarna.abuAbu => 'Abu-abu',
      };

  Color get warna => switch (this) {
        AppThemeWarna.biru => const Color.fromARGB(255, 29, 78, 108),
        AppThemeWarna.merah => const Color.fromARGB(255, 102, 41, 41),
        AppThemeWarna.hijau => const Color.fromARGB(255, 16, 78, 39),
        AppThemeWarna.abuAbu => const Color(0xFF475569),
      };
}

/// Pengaturan aplikasi yang NILAINYA berbeda per varian build (eBisnis vs
/// Al-Bahjah vs produk mendatang) -- padanan [AppVariant] (lihat
/// app_variant.dart) tapi utk hal operasional/preferensi, bukan branding
/// nama/logo. Konstanta compile-time murni spt AppVariant, supaya tiap
/// varian cukup override nilainya di sini tanpa build flag tambahan.
class AppSetting {
  AppSetting._();

  /// Alamat server BAWAAN varian ini. Karena [baseUrlHost] selalu terisi, layar
  /// "Pengaturan Alamat Server" DILEWATI sepenuhnya saat pertama kali
  /// instal -- server sudah dikenal sejak awal (lihat `ServerConfig.muat`
  /// di services/server_config.dart), pengguna langsung ke layar Login.
  ///
  /// Semua varian selain Al-Bahjah memakai server produksi bersama
  /// https://ebisnis.id/ebisnis. Ini mencakup eBisnis umum, Inventory & Sales,
  /// Apotik, dan eMedik. Pengguna TETAP dapat menggantinya melalui
  /// "Ubah Alamat Server" pada layar Masuk.
  ///
  /// Al-Bahjah tetap memakai server khusus
  /// https://ecampus.staialbahjah.ac.id/albahjah, dan eKantin Petra memakai
  /// https://kantinpcu.ecampus.id/petra.
  static const String baseUrlHost = AppVariant.isAlBahjah
      ? 'ecampus.staialbahjah.ac.id'
      : (AppVariant.isNahl
          ? 'an-nahl.santri.info'
          : (AppVariant.isPetra ? 'kantinpcu.ecampus.id' : 'ebisnis.id'));
  static const String baseUrlContextPath = AppVariant.isAlBahjah
      ? 'albahjah'
      : (AppVariant.isNahl
          ? 'nahl'
          : (AppVariant.isPetra ? 'petra' : 'ebisnis'));
  static const bool baseUrlHttps = true;

  /// Warna tema BAWAAN varian ini, sebelum pengguna pernah mengubahnya
  /// sendiri lewat Konfigurasi. Al-Bahjah: hijau (mengikuti warna korporat
  /// logo -- lihat juga aksen emas tambahan di `AppTheme._base` dan sidebar
  /// hijau di `AppColors`, keduanya HANYA aktif utk varian ini). Varian lain
  /// tetap biru spt sebelumnya.
  static const AppThemeWarna temaBawaan =
      AppVariant.isAlBahjah || AppVariant.isNahl
          ? AppThemeWarna.hijau
          : AppThemeWarna.biru;
}
