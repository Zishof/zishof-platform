import 'package:flutter/material.dart';

import '../app_variant.dart';

/// Token warna desain baru (diambil dari 4 referensi screenshot dashboard/
/// kasir/produk/stok yang diberikan user -- sidebar navy gelap, aksen biru,
/// kartu KPI ikon berwarna, badge status pil lembut). Dipakai [AppShell] dan
/// semua layar yang sudah di-reskin (lihat task #191-196) -- layar yang BELUM
/// di-reskin tetap pakai `colorSchemeSeed` lama di main.dart sampai giliran
/// masing-masing, jadi kedua gaya boleh hidup berdampingan selama migrasi.
class AppColors {
  AppColors._();

  /// Sidebar HANYA Al-Bahjah pakai hijau tua+emas korporat (identitas logo);
  /// semua varian lain tetap navy/biru referensi di atas, tak berubah.
  static const sidebarBg =
      AppVariant.isAlBahjah ? Color(0xFF0F2E1A) : Color(0xFF0F1C2E);
  static const sidebarBgActive =
      AppVariant.isAlBahjah ? Color(0xFFCA8A04) : Color(0xFF2563EB);
  static const sidebarText = Color(0xFF8FA0BC);
  static const sidebarTextActive = Colors.white;

  static const pageBg = Color(0xFFF4F6FA);
  static const cardBg = Colors.white;
  static const border = Color(0xFFE5E9F0);

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);

  static const darkPageBg = Color(0xFF0B1220);
  static const darkCardBg = Color(0xFF111827);
  static const darkBorder = Color(0xFF243044);
  static const darkTextPrimary = Color(0xFFE5E7EB);
  static const darkTextSecondary = Color(0xFF94A3B8);

  /// Warna aksen utama aplikasi -- MUTABLE (bukan const) supaya bisa
  /// berubah saat pengguna ganti tema lewat Konfigurasi (lihat
  /// `AppThemeController.ubahWarna` di theme/app_theme.dart). Nilai awal
  /// sengaja disamakan dgn `AppThemeWarna.biru.warna` (lihat app_setting.dart).
  static Color primary = const Color(0xFF2563EB);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFEA580C);
  static const info = Color(0xFF7C3AED);
  static const teal = Color(0xFF0D9488);

  /// Latar lembut proporsional dgn warna solid di atas -- dipakai lingkaran
  /// ikon kartu KPI & badge status (mis. `danger.withValues -> latarLembut(danger)`).
  static Color latarLembut(Color c) => c.withValues(alpha: 0.12);

  static bool gelap(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBgOf(BuildContext context) =>
      gelap(context) ? darkPageBg : pageBg;

  static Color cardBgOf(BuildContext context) =>
      gelap(context) ? darkCardBg : cardBg;

  static Color borderOf(BuildContext context) =>
      gelap(context) ? darkBorder : border;

  static Color textPrimaryOf(BuildContext context) =>
      gelap(context) ? darkTextPrimary : textPrimary;

  static Color textSecondaryOf(BuildContext context) =>
      gelap(context) ? darkTextSecondary : textSecondary;
}
