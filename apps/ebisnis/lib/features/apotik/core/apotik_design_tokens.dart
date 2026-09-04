import 'package:flutter/material.dart';

/// <h3>Token desain varian Apotik — sumber tunggal warna/radius/jarak.</h3>
///
/// Dipasang sebagai [ThemeExtension] sehingga layar mengambilnya lewat
/// `ApotikDesignTokens.of(context)`, BUKAN hard-code warna per widget
/// (temuan audit `docs/apotik-uiux/00-current-state-audit.md`).
///
/// Nilai light mengikuti §7.1 dokumen perintah (teal farmasi, bukan biru POS
/// umum). Varian gelap disediakan agar layar tidak "putih menyilaukan" saat
/// tema gelap aktif; prioritas kebenaran warna tetap pada light production.
@immutable
class ApotikDesignTokens extends ThemeExtension<ApotikDesignTokens> {
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color navigationDark;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Varian **teks** dari warna status. Warna status penuh
  /// ([success]/[warning]/[danger]) dipilih agar mencolok sebagai ikon, garis
  /// tepi, dan latar tipis — pada latar terang rasio kontrasnya hanya 3,0–3,3:1,
  /// yang lolos ambang WCAG untuk GRAFIS (3:1) tetapi TIDAK untuk teks
  /// (4,5:1). Label status apotik berukuran kecil dan membawa arti keselamatan
  /// ("Kedaluwarsa", "Lot ditahan"), jadi teksnya memakai varian gelap ini
  /// sementara ikon dan bingkainya tetap memakai warna penuh.
  /// Dijaga oleh `test/apotik_kontras_test.dart`.
  final Color successText;
  final Color warningText;
  final Color dangerText;

  /// Ungu klinis: dipakai KHUSUS penanda konteks klinis (resep, telaah,
  /// racikan) supaya tidak tertukar dengan status sukses/gagal transaksi.
  final Color clinicalPurple;

  const ApotikDesignTokens({
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.navigationDark,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.successText,
    required this.warningText,
    required this.dangerText,
    required this.clinicalPurple,
  });

  static const ApotikDesignTokens light = ApotikDesignTokens(
    primary: Color(0xFF0F766E),
    primaryStrong: Color(0xFF0B5F59),
    primarySoft: Color(0xFFDDF8F3),
    navigationDark: Color(0xFF0B1F33),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF3F6FA),
    border: Color(0xFFDDE5EF),
    textPrimary: Color(0xFF182538),
    // Digelapkan dari #64748B: pada latar `surfaceMuted` warna lama hanya
    // mencapai 4,39:1 -- di bawah ambang AA untuk teks berukuran normal.
    textSecondary: Color(0xFF5B6878),
    success: Color(0xFF16A34A),
    // Digelapkan dari #D97706: sebagai IKON di atas surfaceMuted warna lama
    // hanya 2,94:1 -- di bawah ambang grafis 3:1.
    warning: Color(0xFFC86D05),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    successText: Color(0xFF116B31),
    warningText: Color(0xFF96500B),
    dangerText: Color(0xFFB91C1C),
    clinicalPurple: Color(0xFF7C3AED),
  );

  static const ApotikDesignTokens dark = ApotikDesignTokens(
    primary: Color(0xFF2DD4BF),
    primaryStrong: Color(0xFF14B8A6),
    primarySoft: Color(0xFF10312E),
    navigationDark: Color(0xFF06131F),
    surface: Color(0xFF111827),
    surfaceMuted: Color(0xFF0B1220),
    border: Color(0xFF243044),
    textPrimary: Color(0xFFE5E7EB),
    textSecondary: Color(0xFF94A3B8),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
    // Pada latar gelap warna status penuh sudah jauh di atas 4,5:1, jadi
    // varian teksnya sengaja sama -- tidak ada gunanya memucatkannya lagi.
    successText: Color(0xFF4ADE80),
    warningText: Color(0xFFFBBF24),
    dangerText: Color(0xFFF87171),
    clinicalPurple: Color(0xFFA78BFA),
  );

  /// Radius & jarak (§7.3). Konstanta, bukan bagian ThemeExtension, karena
  /// tidak pernah berbeda antar tema.
  static const double radiusCard = 14;
  static const double radiusControl = 10;
  static const double gridSpacing = 12;
  static const double pagePaddingDesktop = 20;
  static const double pagePaddingMobile = 12;

  /// Bayangan sangat halus — dokumen melarang glow berlebihan.
  static List<BoxShadow> get shadowCard => const [
        BoxShadow(
            color: Color(0x0F0B1F33), blurRadius: 10, offset: Offset(0, 2)),
      ];

  /// Ambil token dari context; jatuh ke [light] bila ekstensi belum dipasang
  /// (mis. widget diuji berdiri sendiri) supaya tidak pernah melempar.
  static ApotikDesignTokens of(BuildContext context) =>
      Theme.of(context).extension<ApotikDesignTokens>() ?? light;

  @override
  ApotikDesignTokens copyWith({
    Color? primary,
    Color? primaryStrong,
    Color? primarySoft,
    Color? navigationDark,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? successText,
    Color? warningText,
    Color? dangerText,
    Color? clinicalPurple,
  }) {
    return ApotikDesignTokens(
      primary: primary ?? this.primary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      primarySoft: primarySoft ?? this.primarySoft,
      navigationDark: navigationDark ?? this.navigationDark,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      successText: successText ?? this.successText,
      warningText: warningText ?? this.warningText,
      dangerText: dangerText ?? this.dangerText,
      clinicalPurple: clinicalPurple ?? this.clinicalPurple,
    );
  }

  @override
  ApotikDesignTokens lerp(ThemeExtension<ApotikDesignTokens>? other, double t) {
    if (other is! ApotikDesignTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return ApotikDesignTokens(
      primary: c(primary, other.primary),
      primaryStrong: c(primaryStrong, other.primaryStrong),
      primarySoft: c(primarySoft, other.primarySoft),
      navigationDark: c(navigationDark, other.navigationDark),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      info: c(info, other.info),
      successText: c(successText, other.successText),
      warningText: c(warningText, other.warningText),
      dangerText: c(dangerText, other.dangerText),
      clinicalPurple: c(clinicalPurple, other.clinicalPurple),
    );
  }
}
