import 'dart:convert';
import 'dart:ffi';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:win32/win32.dart';
import '../sesi.dart';

/// Buka Layar Pelanggan sbg jendela desktop KEDUA sungguhan (padanan
/// `new BrowserWindow` + `screen.getAllDisplays()` di main.js Electron) --
/// BUKAN `Navigator.push` di jendela yang sama spt sebelumnya. Windows-only;
/// pemanggil (kasir_screen.dart) tetap pakai Navigator.push biasa di Android.
///
/// `desktop_multi_window` v0.3.0 TIDAK punya API setFrame/posisi bawaan
/// (cuma show/hide) -- posisi & ukuran jendela baru diatur manual lewat FFI
/// `SetWindowPos` (paket `win32`, sudah dipakai Buka Laci), HWND-nya
/// ditemukan dgn membandingkan daftar jendela proses ini SEBELUM & SESUDAH
/// `WindowController.create` (selisihnya = jendela yang baru dibuat).
Future<void> bukaLayarPelangganJendelaKedua() async {
  final argumen = jsonEncode({
    'tokoId': Sesi.instance.tokoId,
    'tokoNama': Sesi.instance.tokoNama,
    'pesanTerimaKasih': Sesi.instance.pesanTerimaKasih,
  });

  final sebelum = _semuaHwndProsesIni();
  final controller = await WindowController.create(WindowConfiguration(arguments: argumen, hiddenAtLaunch: true));
  // Beri waktu proses native window (thread pesan Win32 + engine Flutter
  // barunya) benar-benar terbentuk sebelum di-enumerasi ulang.
  await Future.delayed(const Duration(milliseconds: 400));
  final sesudah = _semuaHwndProsesIni();
  final hwndBaru = sesudah.where((h) => !sebelum.contains(h)).toList();

  if (hwndBaru.isNotEmpty) {
    final hwnd = hwndBaru.first;
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      final sekunder = displays.where((d) => d.id != primary.id).toList();
      if (sekunder.isNotEmpty) {
        // Ada monitor kedua -- isi PERSIS bounds-nya, padanan
        // `hitungBoundsMonitorKedua`+`fullScreen(true)` di Electron.
        final d = sekunder.first;
        final skala = (d.scaleFactor ?? 1).toDouble();
        final posisi = d.visiblePosition ?? Offset.zero;
        final ukuran = d.visibleSize ?? d.size;
        SetWindowPos(
          hwnd,
          0,
          (posisi.dx * skala).round(),
          (posisi.dy * skala).round(),
          (ukuran.width * skala).round(),
          (ukuran.height * skala).round(),
          SET_WINDOW_POS_FLAGS.SWP_NOZORDER,
        );
      } else {
        // Cuma satu monitor -- jendela normal yg bisa diseret manual ke
        // monitor kedua nanti, sama seperti fallback Electron saat testing.
        SetWindowPos(hwnd, 0, 100, 100, 1280, 800, SET_WINDOW_POS_FLAGS.SWP_NOZORDER);
      }
    } catch (_) {
      // Gagal deteksi monitor -- tetap tampilkan jendela apa adanya drpd gagal total.
    }
  }
  await controller.show();
}

List<int> _hasilEnumHwnd = [];
int _pidTarget = 0;

int _enumWindowsCallback(int hwnd, int lParam) {
  final pidPtr = calloc<Uint32>();
  try {
    GetWindowThreadProcessId(hwnd, pidPtr);
    if (pidPtr.value == _pidTarget) _hasilEnumHwnd.add(hwnd);
  } finally {
    calloc.free(pidPtr);
  }
  return 1; // lanjutkan enumerasi
}

List<int> _semuaHwndProsesIni() {
  _hasilEnumHwnd = [];
  _pidTarget = GetCurrentProcessId();
  EnumWindows(Pointer.fromFunction<WNDENUMPROC>(_enumWindowsCallback, 0), 0);
  return List.of(_hasilEnumHwnd);
}
