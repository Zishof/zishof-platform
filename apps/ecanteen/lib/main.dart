import 'package:flutter/material.dart';

import 'app_config.dart';
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
    final skema = ColorScheme.fromSeed(seedColor: const Color(0xFF1B6FE3));
    return MaterialApp(
      title: AppConfig.namaAplikasi,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: skema,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
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
