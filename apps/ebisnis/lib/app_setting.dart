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
        AppThemeWarna.biru => const Color(0xFF2563EB),
        AppThemeWarna.merah => const Color(0xFFDC2626),
        AppThemeWarna.hijau => const Color(0xFF16A34A),
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

  /// Alamat server BAWAAN varian ini. Kalau [baseUrlHost] terisi, layar
  /// "Pengaturan Alamat Server" DILEWATI sepenuhnya saat pertama kali
  /// instal -- server sudah dikenal sejak awal (lihat `ServerConfig.muat`
  /// di services/server_config.dart), pengguna langsung ke layar Login.
  ///
  /// Kosongkan (null) utk varian yang dipakai multi-institusi dgn server
  /// berbeda-beda per pelanggan (spt eBisnis pada umumnya, satu APK/EXE
  /// dipakai banyak toko independen) -- isi HANYA utk varian ber-server
  /// bawaan. Al-Bahjah: https://ecampus.staialbahjah.ac.id/albahjah (2026-08-12,
  /// menggantikan siraj.albahjah.or.id lama).
  /// Inventory & Sales/eMedik: default https://dev.ecampus.id/ecampus
  /// (permintaan pemilik utk fase dev/pilot) -- pengguna TETAP bisa
  /// menggantinya kapan saja lewat "Ubah Alamat Server" di layar Masuk.
  static const String? baseUrlHost = AppVariant.isAlBahjah
      ? 'ecampus.staialbahjah.ac.id'
      : (AppVariant.isInventorySales || AppVariant.isEmedik
          ? 'dev.ecampus.id'
          : null);
  static const String baseUrlContextPath = AppVariant.isAlBahjah
      ? 'albahjah'
      : (AppVariant.isInventorySales || AppVariant.isEmedik
          ? 'ecampus'
          : 'ebisnis');
  static const bool baseUrlHttps = true;

  /// Warna tema BAWAAN varian ini, sebelum pengguna pernah mengubahnya
  /// sendiri lewat Konfigurasi. Al-Bahjah: hijau (mengikuti warna korporat
  /// logo -- lihat juga aksen emas tambahan di `AppTheme._base` dan sidebar
  /// hijau di `AppColors`, keduanya HANYA aktif utk varian ini). Varian lain
  /// tetap biru spt sebelumnya.
  static const AppThemeWarna temaBawaan =
      AppVariant.isAlBahjah ? AppThemeWarna.hijau : AppThemeWarna.biru;
}
