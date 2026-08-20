import 'package:flutter/material.dart';

import '../app_variant.dart';

/// Token warna eCanteen.
///
/// Sengaja disamakan dengan POS Desktop (apps/ebisnis `AppColors`) supaya
/// petugas dan anggota melihat satu keluarga tampilan: sidebar navy, aksen
/// biru, halaman abu sangat terang, kartu putih.
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
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);

  /// Gradasi kartu saldo di Beranda -- dua nada dari warna identitas varian.
  /// Dipakai HANYA pada satu kartu; sisanya tetap datar supaya halaman tidak
  /// ramai.
  static const gradasiSaldoAwal =
      AppVariant.isPetra ? Color(0xFF1565D8) : Color(0xFF1E3A5F);
  static const gradasiSaldoAkhir =
      AppVariant.isPetra ? Color(0xFF0D47A1) : Color(0xFF16293F);

  /// Warna latar layar Masuk. Identitas VARIAN build, dipakai sebelum
  /// identitas pengguna diketahui -- nilainya disamakan dgn POS Desktop.
  static const latarMasuk =
      AppVariant.isPetra ? Color(0xFF1565D8) : Color(0xFF1E3A5F);
}
