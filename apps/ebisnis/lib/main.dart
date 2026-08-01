import 'dart:async';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'screens/login_screen.dart';
import 'screens/kasir_screen.dart';

/// Penangkap error global (padanan error-capture.js Electron) -- setiap
/// exception Flutter tak tertangani (widget build error) DAN setiap error
/// async tak tertangani (Future/Stream/isolate) ditulis ke `error_log` lokal
/// yang sama dgn yang dipakai LogErrorScreen, supaya sebelumnya app diam-diam
/// menelan crash tanpa jejak sama sekali -- sekarang selalu ada catatannya.
void main() {
  runZonedGuarded(() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CoreDb.instance.catatErrorLog(
        sumber: 'flutter',
        tingkat: 'ERROR',
        pesan: details.exceptionAsString(),
        detail: details.stack?.toString(),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CoreDb.instance.catatErrorLog(sumber: 'flutter', tingkat: 'ERROR', pesan: error.toString(), detail: stack.toString());
      return true;
    };
    runApp(const EBisnisApp());
  }, (error, stack) {
    CoreDb.instance.catatErrorLog(sumber: 'zone', tingkat: 'ERROR', pesan: error.toString(), detail: stack.toString());
  });
}

class EBisnisApp extends StatelessWidget {
  const EBisnisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eBisnis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1E3A5F),
        useMaterial3: true,
      ),
      home: const _GerbangAwal(),
    );
  }
}

/// Cek token tersimpan (login sebelumnya) sebelum menampilkan layar pertama --
/// kalau ada, langsung ke KasirScreen; kalau tidak, ke LoginScreen.
class _GerbangAwal extends StatefulWidget {
  const _GerbangAwal();

  @override
  State<_GerbangAwal> createState() => _GerbangAwalState();
}

class _GerbangAwalState extends State<_GerbangAwal> {
  bool _memeriksa = true;

  @override
  void initState() {
    super.initState();
    _periksaToken();
  }

  Future<void> _periksaToken() async {
    await ApiClient.instance.muatTokenTersimpan();
    await IdentitasMesin.instance.muat();
    if (mounted) setState(() => _memeriksa = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_memeriksa) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ApiClient.instance.sudahLogin ? const KasirScreen() : const LoginScreen();
  }
}
