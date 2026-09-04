import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_setting.dart';
import '../app_variant.dart';
import '../features/apotik/core/apotik_design_tokens.dart';
import 'app_colors.dart';

/// Pengelola tema ringan tanpa dependency state-management tambahan.
///
/// FlareLine memakai provider untuk theme toggle; di POS ini cukup
/// ValueNotifier supaya bootstrap tetap murah dan tidak menambah paket baru.
class AppThemeController {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();

  static const _kunciModeTema = 'ebisnis_theme_mode';
  static const _kunciWarnaTema = 'ebisnis_theme_warna';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  /// Warna aksen aplikasi -- default [AppSetting.temaBawaan] sebelum
  /// pengguna pernah memilih sendiri lewat Konfigurasi. [muat] menyamakan
  /// [AppColors.primary] dgn nilai ini sedini mungkin (sebelum `runApp`),
  /// jadi frame pertama sudah memakai warna yang benar (tidak flash biru
  /// lalu berubah).
  final ValueNotifier<AppThemeWarna> warna =
      ValueNotifier(AppSetting.temaBawaan);

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    final tersimpan = sp.getString(_kunciModeTema);
    mode.value = tersimpan == 'dark' ? ThemeMode.dark : ThemeMode.light;

    final warnaTersimpan = sp.getString(_kunciWarnaTema);
    warna.value = AppThemeWarna.values.firstWhere(
      (w) => w.name == warnaTersimpan,
      orElse: () => AppSetting.temaBawaan,
    );
    AppColors.primary = warna.value.warna;
  }

  Future<void> ubah(bool gelap) async {
    mode.value = gelap ? ThemeMode.dark : ThemeMode.light;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciModeTema, gelap ? 'dark' : 'light');
  }

  Future<void> toggle() => ubah(mode.value != ThemeMode.dark);

  Future<void> ubahWarna(AppThemeWarna w) async {
    warna.value = w;
    AppColors.primary = w.warna;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciWarnaTema, w.name);
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.pageBg,
        surface: AppColors.cardBg,
        onSurface: AppColors.textPrimary,
      );

  static ThemeData dark() => _base(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkPageBg,
        surface: AppColors.darkCardBg,
        onSurface: AppColors.darkTextPrimary,
      );

  /// Aksen "kuning tua" korporat Al-Bahjah (lihat logo) -- dipakai sbg
  /// `ColorScheme.secondary` HANYA utk varian ini, memberi widget Material
  /// bawaan (mis. FloatingActionButton/Switch) sentuhan emas di samping
  /// hijau [AppColors.primary]. Varian lain tetap sepenuhnya seed-generated
  /// spt sebelumnya (tak ada perubahan visual).
  static const _emasAlBahjah = Color(0xFFCA8A04);

  static ThemeData _base({
    required Brightness brightness,
    required Color scaffoldBackgroundColor,
    required Color surface,
    required Color onSurface,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: surface,
      onSurface: onSurface,
      secondary: AppVariant.isAlBahjah ? _emasAlBahjah : null,
      onSecondary: AppVariant.isAlBahjah ? Colors.white : null,
    );
    final border =
        brightness == Brightness.dark ? AppColors.darkBorder : AppColors.border;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      dividerColor: border,
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor:
            brightness == Brightness.dark ? AppColors.sidebarBg : Colors.white,
        foregroundColor: onSurface,
      ),
      tabBarTheme: TabBarTheme(
        labelColor: AppColors.primary,
        unselectedLabelColor: brightness == Brightness.dark
            ? AppColors.darkTextSecondary
            : AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: border,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary),
        ),
        isDense: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      // Token semantik varian APOTIK saja (ThemeExtension). Varian lain tidak
      // menerima ekstensi ini sehingga branding globalnya TIDAK berubah
      // (aturan multi-varian Sec.4.2 dokumen modernisasi). Layar apotik membaca
      // lewat ApotikDesignTokens.of(context).
      extensions: AppVariant.isApotik
          ? <ThemeExtension<dynamic>>[
              brightness == Brightness.dark
                  ? ApotikDesignTokens.dark
                  : ApotikDesignTokens.light,
            ]
          : const <ThemeExtension<dynamic>>[],
    );
  }
}
