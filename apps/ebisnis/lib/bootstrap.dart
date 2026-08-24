import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:core_update/core_update.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'app_variant.dart';
import 'product_profile.dart';
import 'screens/layar_pelanggan_screen.dart';
import 'screens/apotik/layar_antrean_farmasi_screen.dart';
import 'screens/layar_kunci_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pengaturan_server_screen.dart';
import 'services/face_onnx/pasang_provider_wajah.dart';
import 'services/master_offline.dart';
import 'services/pengaturan_update.dart';
import 'services/prefs_guard.dart';
import 'services/pengaturan_sesi_lokal.dart';
import 'services/transaksi_outbox_service.dart';
import 'services/server_config.dart';
import 'theme/app_theme.dart';
import 'widgets/safe_state.dart';

/// <h3>Bootstrap bersama semua entrypoint varian (PERINTAH_MASTER §4.1).</h3>
///
/// Dulu seluruh isi fungsi ini hidup langsung di `main.dart:main()`; dipindah
/// ke sini supaya `main.dart` (varian eBisnis/Al-Bahjah) dan
/// `main_inventory_sales.dart` (varian Inventory & Sales) berbagi SATU kode
/// inisialisasi -- yang membedakan hanya [AppProductProfile] yang dioper.
///
/// Penangkap error global (padanan error-capture.js Electron) -- setiap
/// exception Flutter tak tertangani (widget build error) DAN setiap error
/// async tak tertangani (Future/Stream/isolate) ditulis ke `error_log` lokal
/// yang sama dgn yang dipakai LogErrorScreen.
///
/// `desktop_multi_window` (Windows) membuat jendela kedua (Layar Pelanggan)
/// DALAM PROSES yang sama (engine Flutter terpisah, BUKAN exe/proses baru) --
/// `main()` SELALU dijalankan tanpa argumen pembeda; satu-satunya cara tiap
/// engine tahu "apakah aku jendela kedua" adalah bertanya ke native side lewat
/// `WindowController.fromCurrentEngine()`.
Future<void> bootstrap(AppProductProfile profil) async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // WAJIB sebelum apa pun menyentuh SharedPreferences -- langsung maupun
    // lewat AppThemeController/ServerConfig. `main.dart` (varian eBisnis)
    // sudah memanggilnya sejak awal, tetapi bootstrap bersama ini TIDAK,
    // sehingga varian apotik/emedik/inventory_sales/mitrainap kehilangan
    // penjaganya: satu file preferensi korup (mati listrik saat menulis)
    // membuat getInstance() melempar, exception-nya ditelan zone guard, dan
    // `runApp` di bawah TIDAK PERNAH dipanggil -- jendela dibuat tetapi tidak
    // pernah dirender, jadi aplikasi tampak tidak bisa dibuka sama sekali
    // tanpa pesan apa pun. Lihat JavaDoc [PrefsGuard].
    await PrefsGuard.perbaikiJikaKorup();
    AppProductProfile.aktif = profil;
    CoreDb.configureStorage(AppVariant.storageNamespace);
    // Semua varian modern (termasuk Nahl) masuk melalui bootstrap(), bukan
    // main.dart lama. Muat data locale sebelum widget pertama dibangun agar
    // DateFormat(..., 'id_ID') pada SO Harian dan layar lain tidak melempar
    // LocaleDataException lalu berubah menjadi panel abu-abu kosong.
    await initializeDateFormatting('id_ID', null);
    if (!profil.cocokDenganDartDefine()) {
      // Build salah kombinasi (entrypoint vs --dart-define) -- jangan diam:
      // branding compile-time (judul jendela/ikon/exe Windows) akan berbeda
      // dari perilaku runtime. Tercatat ke error_log supaya ketahuan di QA.
      CoreDb.instance.catatErrorLog(
        sumber: 'bootstrap',
        tingkat: 'ERROR',
        pesan:
            'Entrypoint profil "${profil.kode}" tidak cocok dgn --dart-define EBISNIS_VARIANT="${AppVariant.kode}". '
            'Build ulang dgn kombinasi -t dan --dart-define yang konsisten.',
      );
    }
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(ApiClient.instance.catatError(details.exception,
          stack: details.stack, sumber: 'flutter'));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(ApiClient.instance
          .catatError(error, stack: stack, sumber: 'platform'));
      return true;
    };

    String argumenJendela = '';
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // BUG (fixed): native `MultiWindowManager::Create` (desktop_multi_window
      // 0.3.0) mendaftarkan wrapper jendela baru DUA KALI -- Dart `main()`
      // jendela kedua bisa sempat memanggil `fromCurrentEngine()` di antara
      // kedua pendaftaran dan dapat arguments kosong -> keliru dianggap
      // jendela utama. Coba ulang beberapa kali (jeda pendek) sampai
      // arguments terisi ATAU batas percobaan habis (jendela utama memang
      // SELALU kosong). Detail: lihat riwayat main.dart sebelum refactor.
      for (var percobaan = 0; percobaan < 4; percobaan++) {
        try {
          final controller = await WindowController.fromCurrentEngine();
          argumenJendela = controller.arguments;
        } catch (_) {
          // Gagal tanya (mis. platform tak dukung channel ini) -- anggap jendela utama.
        }
        if (argumenJendela.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    if (argumenJendela.isNotEmpty) {
      final argumen = jsonDecode(argumenJendela) as Map<String, dynamic>;
      runApp(_LayarPelangganWindowApp(argumen: argumen));
      return;
    }

    await AppThemeController.instance.muat();
    // Offline-first master: antrean mutasi yang tersisa dari sesi sebelumnya
    // langsung ikut jadwal kirim ulang begitu app dibuka -- tidak menunggu
    // user membuka salah satu layar master dulu.
    MasterOffline.pastikanTimer();
    runApp(const EBisnisApp());
  }, (error, stack) {
    unawaited(
        ApiClient.instance.catatError(error, stack: stack, sumber: 'zone'));
  });
}

/// Aplikasi MINIMAL utk jendela desktop kedua (Layar Pelanggan) -- TIDAK
/// lewat gerbang login/Sesi spt `EBisnisApp` biasa (jendela ini bukan sesi
/// kasir baru, cuma menampilkan siaran dari jendela kasir yg sudah login).
class _LayarPelangganWindowApp extends StatefulWidget {
  final Map<String, dynamic> argumen;
  const _LayarPelangganWindowApp({required this.argumen});

  @override
  State<_LayarPelangganWindowApp> createState() =>
      _LayarPelangganWindowAppState();
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
    if (mounted) setStateIfMounted(() => _siap = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1E3A5F), useMaterial3: true),
      home: !_siap
          ? const Scaffold(
              backgroundColor: Color(0xFF0F1C2E),
              body: Center(child: CircularProgressIndicator()))
          : widget.argumen['jenisJendela'] == 'antrean_farmasi'
              ? LayarAntreanFarmasiScreen(
                  jendelaKedua: true,
                  tokoIdOverride: widget.argumen['tokoId'] as int?,
                  tokoNamaOverride: widget.argumen['tokoNama'] as String?,
                  mode:
                      ModeLayarFarmasiX.dari(widget.argumen['mode'] as String?),
                )
              : LayarPelangganScreen(
                  jendelaKedua: true,
                  tokoIdOverride: widget.argumen['tokoId'] as int?,
                  tokoNamaOverride: widget.argumen['tokoNama'] as String?,
                  pesanTerimaKasihOverride:
                      widget.argumen['pesanTerimaKasih'] as String?,
                ),
    );
  }
}

class EBisnisApp extends StatefulWidget {
  const EBisnisApp({super.key});

  @override
  State<EBisnisApp> createState() => _EBisnisAppState();
}

class _EBisnisAppState extends State<EBisnisApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Provider wajah on-device (YuNet+SFace/ONNX) -- fail-closed bila model
    // belum diunduh; lihat pasang_provider_wajah.dart.
    pasangProviderWajahOnDevice();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (ApiClient.instance.sudahLogin) {
        unawaited(PengaturanSesiLokal.instance.catatAktifSekarang());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.instance.mode,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: kunciNavigatorUtama,
        title: AppProductProfile.aktif.namaAplikasi,
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const _GerbangAwal(),
      ),
    );
  }
}

/// Cek token tersimpan (login sebelumnya) sebelum menampilkan layar pertama --
/// kalau ada, langsung ke layar awal profil aktif; kalau tidak, ke LoginScreen.
class _GerbangAwal extends StatefulWidget {
  const _GerbangAwal();

  @override
  State<_GerbangAwal> createState() => _GerbangAwalState();
}

class _GerbangAwalState extends State<_GerbangAwal> {
  bool _memeriksa = true;
  bool _perluSetupServer = false;

  /// Token masih ada tetapi sesi terkunci karena aplikasi lama tidak dipakai --
  /// lihat [LayarKunciScreen].
  bool _terkunci = false;
  InfoUpdate? _infoUpdate;
  StreamSubscription<void>? _sesiBerakhirSubscription;

  @override
  void initState() {
    super.initState();
    _sesiBerakhirSubscription = ApiClient.instance.sesiBerakhir.listen((_) {
      if (!mounted) return;
      setStateIfMounted(() => _terkunci = false);
    });
    _periksaToken();
    _cekUpdate();
  }

  @override
  void dispose() {
    _sesiBerakhirSubscription?.cancel();
    super.dispose();
  }

  Future<void> _periksaToken() async {
    // Alamat server WAJIB diatur dulu (sekali di awal) sebelum apa pun lain
    // -- padanan gerbang setup.html/main.js desktop-pos-electron: satu
    // APK/EXE eBisnis harus bisa dipakai institusi mana pun, jadi baseUrl
    // TIDAK BOLEH hardcode (lihat ServerConfig/ApiClient.baseUrl).
    await ServerConfig.instance.muat();
    if (!ServerConfig.instance.sudahDiatur) {
      if (mounted) setStateIfMounted(() => _perluSetupServer = true);
      return;
    }
    await ApiClient.instance.muatTokenTersimpan();
    if (ApiClient.instance.sudahLogin) {
      // Batas waktu lokal MENGUNCI, tidak menghapus token. Token perangkat
      // berlaku 30 hari di server (PosDeviceAuthApi.MASA_BERLAKU_HARI);
      // membuangnya karena aplikasi lama tidak dibuka memaksa login daring
      // pada saat yang paling buruk -- pagi hari saat server belum hidup --
      // padahal seluruh jalur luring (katalog, antrean transaksi) siap. Token
      // hanya dibuang bila pengguna keluar akun atau server menolaknya.
      final kedaluwarsa = await PengaturanSesiLokal.instance.sudahKedaluwarsa();
      if (kedaluwarsa) {
        setStateIfMounted(() => _terkunci = true);
      } else {
        await PengaturanSesiLokal.instance.catatAktifSekarang();
        TransaksiOutboxService.instance.mulai();
      }
    }
    await IdentitasMesin.instance.muat();
    if (mounted) setStateIfMounted(() => _memeriksa = false);
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
        assetKeyword: AppProductProfile.aktif.updateAssetKeyword,
        tagPrefix: AppProductProfile.aktif.tagRilisPrefix,
      );
      final tersediaUntukPerangkat = hasil != null &&
          (defaultTargetPlatform == TargetPlatform.android
              ? hasil.urlApk != null
              : (hasil.urlExe != null || hasil.urlPaketWindows != null));
      if (mounted && tersediaUntukPerangkat) {
        final dipasang = await PengaturanUpdate.instance
            .cobaPasangOtomatis(hasil)
            .catchError((_) => false);
        if (!dipasang && mounted) {
          setStateIfMounted(() => _infoUpdate = hasil);
        }
      }
    } catch (_) {
      // Gagal cek (offline/rate-limit) -- diam saja, bukan alasan mengganggu.
    }
  }

  Future<void> _bukaUnduhan() async {
    final info = _infoUpdate;
    if (info == null) return;
    final url = defaultTargetPlatform == TargetPlatform.android
        ? info.urlApk
        : info.urlExe;
    if (url == null) return;
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
    final layar = !ApiClient.instance.sudahLogin
        ? const LoginScreen()
        : _terkunci
            ? const LayarKunciScreen()
            : AppProductProfile.aktif.buatLayarAwal();
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_alt,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Versi ${_infoUpdate!.versi} tersedia',
                          style: const TextStyle(color: Colors.white)),
                    ),
                    TextButton(
                        onPressed: _bukaUnduhan,
                        child: const Text('Unduh',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 18),
                        onPressed: () =>
                            setStateIfMounted(() => _infoUpdate = null)),
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
