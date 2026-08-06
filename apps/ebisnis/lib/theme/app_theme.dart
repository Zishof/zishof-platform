import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// Pengelola tema ringan tanpa dependency state-management tambahan.
///
/// FlareLine memakai provider untuk theme toggle; di POS ini cukup
/// ValueNotifier supaya bootstrap tetap murah dan tidak menambah paket baru.
class AppThemeController {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();

  static const _kunciModeTema = 'ebisnis_theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    final tersimpan = sp.getString(_kunciModeTema);
    mode.value = tersimpan == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> ubah(bool gelap) async {
    mode.value = gelap ? ThemeMode.dark : ThemeMode.light;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kunciModeTema, gelap ? 'dark' : 'light');
  }

  Future<void> toggle() => ubah(mode.value != ThemeMode.dark);
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
          borderSide: const BorderSide(color: AppColors.primary),
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
    );
  }
}
