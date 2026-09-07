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

  /// POS tiga area (konteks · katalog · keranjang) hanya dipakai pada desktop
  /// benar-benar lebar. Pada desktop standard, ruang sesudah sidebar aplikasi
  /// lebih berguna untuk katalog + keranjang tetap (dua area).
  bool get bolehTigaArea => this == ApotikLayout.desktopWide;

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

  /// Lebar panel isi minimum agar katalog dan keranjang 360 px dapat tampil
  /// berdampingan. Nilai ini sengaja dihitung dari constraint halaman POS,
  /// bukan lebar monitor, karena sidebar aplikasi sudah mengambil ruang.
  static const double keranjangTetap = 980;

  /// Sasaran sentuh minimum Android (§8, 44–48 dp).
  static const double targetSentuhMinimum = 48;

  static ApotikLayout dariLebar(double lebar) {
    if (lebar < tablet) return ApotikLayout.compactMobile;
    if (lebar < desktopCompact) return ApotikLayout.tablet;
    if (lebar < desktopStandard) return ApotikLayout.desktopCompact;
    if (lebar < desktopWide) return ApotikLayout.desktopStandard;
    return ApotikLayout.desktopWide;
  }

  static bool bolehKeranjangTetap(double lebar) => lebar >= keranjangTetap;

  static ApotikPosCapabilities kemampuanPos(double lebar) =>
      ApotikPosCapabilities(lebar);

  /// Lebar LAYAR, bukan lebar widget — dipakai untuk keputusan navigasi
  /// (bottom nav vs sidebar). Untuk keputusan di dalam panel, pakai
  /// [dariLebar] dengan constraint panel tsb.
  static ApotikLayout dariContext(BuildContext context) =>
      dariLebar(MediaQuery.sizeOf(context).width);

  static double paddingHalaman(ApotikLayout layout) =>
      layout.isDesktop ? 20 : 12;
}

/// Kemampuan layout POS dihitung dari lebar isi aktual setelah AppShell dan
/// sidebar mengambil ruang. Ini mencegah viewport 1366/1440 salah dianggap
/// cukup lebar untuk tiga panel tetap.
class ApotikPosCapabilities {
  final double innerWidth;

  const ApotikPosCapabilities(this.innerWidth);

  bool get bolehKeranjangTetap =>
      innerWidth >= ApotikBreakpoints.keranjangTetap;

  bool get bolehPanelKonteksTetap =>
      innerWidth >= ApotikBreakpoints.desktopWide;

  bool get tampilkanBottomCart => !bolehKeranjangTetap;
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
