import 'package:flutter/material.dart';

import 'app_config.dart';
import 'theme/app_colors.dart';
import 'screens/beranda_screen.dart';
import 'screens/login_screen.dart';
import 'services/server_config.dart';
import 'services/sesi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerConfig.instance.muat();
  await Sesi.instance.muatToken();
  runApp(const ECanteenApp());
}

class ECanteenApp extends StatelessWidget {
  const ECanteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Tema disamakan dgn POS Desktop: halaman abu sangat terang, kartu putih
    // bergaris tipis, aksen biru. Anggota dan petugas jadi melihat satu
    // keluarga tampilan meski aplikasinya berbeda.
    final skema = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    );
    return MaterialApp(
      title: AppConfig.namaAplikasi,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: skema,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.pageBg,
        cardTheme: CardThemeData(
          color: AppColors.cardBg,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.border),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.pageBg,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
        ),
      ),
      // Token yang tersimpan belum tentu masih berlaku; BerandaScreen
      // memverifikasinya lewat kantin_info dan menendang balik ke Login
      // bila server menolak.
      home: Sesi.instance.sudahMasuk
          ? const BerandaScreen()
          : const LoginScreen(),
    );
  }
}
