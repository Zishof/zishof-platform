import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:core_update/core_update.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';
import 'screens/login_screen.dart';
import 'screens/kasir_screen.dart';
import 'screens/layar_pelanggan_screen.dart';
import 'screens/pengaturan_server_screen.dart';
import 'services/server_config.dart';

/// Penangkap error global (padanan error-capture.js Electron) -- setiap
/// exception Flutter tak tertangani (widget build error) DAN setiap error
/// async tak tertangani (Future/Stream/isolate) ditulis ke `error_log` lokal
/// yang sama dgn yang dipakai LogErrorScreen, supaya sebelumnya app diam-diam
/// menelan crash tanpa jejak sama sekali -- sekarang selalu ada catatannya.
///
/// `desktop_multi_window` (Windows) membuat jendela kedua (Layar Pelanggan)
/// DALAM PROSES yang sama (engine Flutter terpisah, BUKAN exe/proses baru --
/// dicek lewat native `multi_window_manager.cc`), jadi `main()` SELALU
/// dijalankan tanpa argumen pembeda apa pun; satu-satunya cara tiap
/// engine tahu "apakah aku jendela kedua" adalah bertanya ke native side lewat
/// `WindowController.fromCurrentEngine()` -- jendela utama mendapat
/// `arguments == ''`, jendela kedua mendapat JSON yg dikirim
/// `kasir_screen.dart._bukaLayarPelanggan`/`layar_kedua.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runZonedGuarded(() async {
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

    String argumenJendela = '';
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final controller = await WindowController.fromCurrentEngine();
        argumenJendela = controller.arguments;
      } catch (_) {
        // Gagal tanya (mis. platform tak dukung channel ini) -- anggap jendela utama.
      }
    }

    if (argumenJendela.isNotEmpty) {
      final argumen = jsonDecode(argumenJendela) as Map<String, dynamic>;
      runApp(_LayarPelangganWindowApp(argumen: argumen));
      return;
    }

    runApp(const EBisnisApp());
  }, (error, stack) {
    CoreDb.instance.catatErrorLog(sumber: 'zone', tingkat: 'ERROR', pesan: error.toString(), detail: stack.toString());
  });
}

/// Aplikasi MINIMAL utk jendela desktop kedua (Layar Pelanggan) -- TIDAK
/// lewat gerbang login/Sesi spt `EBisnisApp` biasa (jendela ini bukan sesi
/// kasir baru, cuma menampilkan siaran dari jendela kasir yg sudah login).
/// Memuat ulang `ServerConfig`+token tersimpan sendiri (engine Flutter
/// terpisah tak mewarisi memori/isolate jendela utama) supaya
/// `ApiClient.aksi('layar_pelanggan_ambil')` tetap terautentikasi;
/// tokoId/tokoNama/pesanTerimaKasih dioper via `argumen` (JSON dari
/// `WindowConfiguration.arguments`) drpd via Sesi.instance.
class _LayarPelangganWindowApp extends StatefulWidget {
  final Map<String, dynamic> argumen;
  const _LayarPelangganWindowApp({required this.argumen});

  @override
  State<_LayarPelangganWindowApp> createState() => _LayarPelangganWindowAppState();
}

class _LayarPelangganWindowAppState extends State<_LayarPelangganWindowApp> {
  bool _siap = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    await ServerConfig.instance.muat();
    await ApiClient.instance.muatTokenTersimpan();
    if (mounted) setState(() => _siap = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1E3A5F), useMaterial3: true),
      home: !_siap
          ? const Scaffold(backgroundColor: Color(0xFF0F1C2E), body: Center(child: CircularProgressIndicator()))
          : LayarPelangganScreen(
              jendelaKedua: true,
              tokoIdOverride: widget.argumen['tokoId'] as int?,
              tokoNamaOverride: widget.argumen['tokoNama'] as String?,
              pesanTerimaKasihOverride: widget.argumen['pesanTerimaKasih'] as String?,
            ),
    );
  }
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
  bool _perluSetupServer = false;
  InfoUpdate? _infoUpdate;

  @override
  void initState() {
    super.initState();
    _periksaToken();
    _cekUpdate();
  }

  Future<void> _periksaToken() async {
    // Alamat server WAJIB diatur dulu (sekali di awal) sebelum apa pun lain
    // -- padanan gerbang setup.html/main.js desktop-pos-electron: satu
    // APK/EXE eBisnis harus bisa dipakai institusi mana pun, jadi baseUrl
    // TIDAK BOLEH hardcode (lihat ServerConfig/ApiClient.baseUrl).
    await ServerConfig.instance.muat();
    if (!ServerConfig.instance.sudahDiatur) {
      if (mounted) setState(() => _perluSetupServer = true);
      return;
    }
    await ApiClient.instance.muatTokenTersimpan();
    await IdentitasMesin.instance.muat();
    if (mounted) setState(() => _memeriksa = false);
  }

  /// Cek rilis GitHub terbaru sekali per buka-app (non-blocking, tak
  /// menunda layar pertama) -- pola distribusi manual (bukan auto-install)
  /// krn Flutter di sini tak dijalankan lewat installer yg bisa mengganti
  /// dirinya sendiri, lihat JavaDoc [UpdateChecker].
  Future<void> _cekUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final hasil = await UpdateChecker.cekTerbaru(
        repoOwner: 'Zishof',
        repoName: 'zishof-platform',
        versiSaatIni: info.version,
      );
      if (mounted && hasil != null) setState(() => _infoUpdate = hasil);
    } catch (_) {
      // Gagal cek (offline/rate-limit) -- diam saja, bukan alasan mengganggu.
    }
  }

  Future<void> _bukaUnduhan() async {
    final info = _infoUpdate;
    if (info == null) return;
    final url = defaultTargetPlatform == TargetPlatform.android ? (info.urlApk ?? info.urlRilis) : (info.urlExe ?? info.urlRilis);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_perluSetupServer) {
      return const PengaturanServerScreen(pertamaKali: true);
    }
    if (_memeriksa) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final layar = ApiClient.instance.sudahLogin ? const KasirScreen() : const LoginScreen();
    if (_infoUpdate == null) return layar;
    return Stack(
      children: [
        layar,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Material(
              color: const Color(0xFF1E3A5F),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_alt, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Versi ${_infoUpdate!.versi} tersedia', style: const TextStyle(color: Colors.white)),
                    ),
                    TextButton(onPressed: _bukaUnduhan, child: const Text('Unduh', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 18), onPressed: () => setState(() => _infoUpdate = null)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
