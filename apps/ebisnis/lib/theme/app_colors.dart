import 'package:flutter/material.dart';

/// Token warna desain baru (diambil dari 4 referensi screenshot dashboard/
/// kasir/produk/stok yang diberikan user -- sidebar navy gelap, aksen biru,
/// kartu KPI ikon berwarna, badge status pil lembut). Dipakai [AppShell] dan
/// semua layar yang sudah di-reskin (lihat task #191-196) -- layar yang BELUM
/// di-reskin tetap pakai `colorSchemeSeed` lama di main.dart sampai giliran
/// masing-masing, jadi kedua gaya boleh hidup berdampingan selama migrasi.
class AppColors {
  AppColors._();

  static const sidebarBg = Color(0xFF0F1C2E);
  static const sidebarBgActive = Color(0xFF2563EB);
  static const sidebarText = Color(0xFF8FA0BC);
  static const sidebarTextActive = Colors.white;

  static const pageBg = Color(0xFFF4F6FA);
  static const cardBg = Colors.white;
  static const border = Color(0xFFE5E9F0);

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);

  static const primary = Color(0xFF2563EB);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFEA580C);
  static const info = Color(0xFF7C3AED);
  static const teal = Color(0xFF0D9488);

  /// Latar lembut proporsional dgn warna solid di atas -- dipakai lingkaran
  /// ikon kartu KPI & badge status (mis. `danger.withValues -> latarLembut(danger)`).
  static Color latarLembut(Color c) => c.withValues(alpha: 0.12);
}
