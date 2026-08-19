import 'package:flutter/widgets.dart';

/// Kelas layout varian Apotik (§8 dokumen perintah).
///
/// Menggantikan pemeriksaan `width >= 900` yang tersebar ad-hoc: satu sumber
/// kebenaran supaya perilaku antar layar konsisten dan dapat diuji.
enum ApotikLayout {
  compactMobile,
  tablet,
  desktopCompact,
  desktopStandard,
  desktopWide;

  bool get isMobile => this == ApotikLayout.compactMobile;
  bool get isTablet => this == ApotikLayout.tablet;

  /// Desktop apa pun (compact ke atas) — dipakai untuk memilih master-detail.
  bool get isDesktop =>
      this == ApotikLayout.desktopCompact ||
      this == ApotikLayout.desktopStandard ||
      this == ApotikLayout.desktopWide;

  /// POS tiga area (konteks · katalog · keranjang) hanya muat mulai 1280 px.
  /// Di bawah itu keranjang menjadi panel yang dapat diciutkan / lembar penuh.
  bool get bolehTigaArea =>
      this == ApotikLayout.desktopStandard || this == ApotikLayout.desktopWide;

  /// Kolom sekunder tabel disembunyikan pada layar sempit (responsive column
  /// priority) supaya kolom berisiko tinggi tetap terbaca.
  bool get sembunyikanKolomSekunder =>
      this == ApotikLayout.compactMobile ||
      this == ApotikLayout.tablet ||
      this == ApotikLayout.desktopCompact;
}

class ApotikBreakpoints {
  const ApotikBreakpoints._();

  static const double tablet = 600;
  static const double desktopCompact = 900;
  static const double desktopStandard = 1280;
  static const double desktopWide = 1600;

  /// Sasaran sentuh minimum Android (§8, 44–48 dp).
  static const double targetSentuhMinimum = 48;

  static ApotikLayout dariLebar(double lebar) {
    if (lebar < tablet) return ApotikLayout.compactMobile;
    if (lebar < desktopCompact) return ApotikLayout.tablet;
    if (lebar < desktopStandard) return ApotikLayout.desktopCompact;
    if (lebar < desktopWide) return ApotikLayout.desktopStandard;
    return ApotikLayout.desktopWide;
  }

  /// Lebar LAYAR, bukan lebar widget — dipakai untuk keputusan navigasi
  /// (bottom nav vs sidebar). Untuk keputusan di dalam panel, pakai
  /// [dariLebar] dengan constraint panel tsb.
  static ApotikLayout dariContext(BuildContext context) =>
      dariLebar(MediaQuery.sizeOf(context).width);

  static double paddingHalaman(ApotikLayout layout) =>
      layout.isDesktop ? 20 : 12;
}

/// Builder ringkas: `ApotikResponsive(builder: (context, layout) => ...)`.
/// Memakai [LayoutBuilder] sehingga panel bersarang pun mendapat kelas yang
/// benar sesuai ruang yang tersedia, bukan sekadar ukuran layar.
class ApotikResponsive extends StatelessWidget {
  final Widget Function(BuildContext context, ApotikLayout layout) builder;
  const ApotikResponsive({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lebar = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return builder(context, ApotikBreakpoints.dariLebar(lebar));
      },
    );
  }
}
