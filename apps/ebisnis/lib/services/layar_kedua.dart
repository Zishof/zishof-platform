import 'dart:convert';
import 'dart:ffi';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:win32/win32.dart';
import '../sesi.dart';

int? _hwndLayarPelanggan;
final List<int> _hwndLayarFarmasi = [];

Future<int> jumlahMonitorTersedia() async {
  final displays = await screenRetriever.getAllDisplays();
  return displays.isEmpty ? 1 : displays.length;
}

/// Selalu membuat jendela baru: layar gabungan, obat jadi, dan racikan dapat
/// dibuka bersamaan pada monitor yang sama maupun monitor berbeda.
Future<void> bukaLayarFarmasiJendelaBaru({
  required String mode,
  required int monitorIndex,
}) async {
  final hwndPetugas = GetForegroundWindow();
  final argumen = jsonEncode({
    'jenisJendela': 'antrean_farmasi',
    'mode': mode,
    'monitorIndex': monitorIndex,
    'tokoId': Sesi.instance.tokoId,
    'tokoNama': Sesi.instance.tokoNama,
  });
  final sebelum = _semuaHwndProsesIni();
  final controller = await WindowController.create(
      WindowConfiguration(arguments: argumen, hiddenAtLaunch: true));
  await Future.delayed(const Duration(milliseconds: 400));
  final sesudah = _semuaHwndProsesIni();
  final baru = sesudah.where((h) => !sebelum.contains(h)).toList();
  if (baru.isNotEmpty) {
    _hwndLayarFarmasi.removeWhere((h) => IsWindow(h) == 0);
    _hwndLayarFarmasi.add(baru.first);
    await _posisikanFullscreenTanpaFrame(baru.first,
        monitorIndex: monitorIndex);
  }
  await controller.show();
  if (hwndPetugas != 0) SetForegroundWindow(hwndPetugas);
}

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
Future<void> toggleLayarPelangganJendelaKedua() async {
  if (tutupLayarPelangganJendelaKedua()) return;
  await bukaLayarPelangganJendelaKedua();
}

Future<void> bukaLayarPelangganJendelaKedua() async {
  if (_hwndLayarPelanggan != null && IsWindow(_hwndLayarPelanggan!) != 0) {
    SetForegroundWindow(_hwndLayarPelanggan!);
    return;
  }

  // Gap-closure "KeyDownEvent... state shows physical key is already
  // pressed" (assertion `hardware_keyboard.dart`, dipicu jendela ini dibuka
  // via tombol F9): `ShowWindow(SW_SHOWMAXIMIZED)` di bawah MENGAKTIFKAN
  // jendela baru (merebut fokus OS dari jendela kasir). Kalau ada physical
  // key yg masih tertekan saat itu (mis. scanner barcode msh mengirim
  // keystroke), KeyUp-nya terkirim ke jendela BARU (yg engine Flutter-nya
  // beda), bukan ke jendela kasir yg menerima KeyDown-nya -- `_pressedKeys`
  // di jendela kasir jadi permanen "nyangkut" sampai app direstart. Simpan
  // HWND kasir SEBELUM jendela kedua dibuat, lalu rebut fokus balik
  // stlh selesai -- sekalian UX yg lebih benar (kasir tak perlu klik ulang
  // ke layarnya sendiri stlh membuka Layar Pelanggan).
  final hwndKasir = GetForegroundWindow();

  final argumen = jsonEncode({
    'tokoId': Sesi.instance.tokoId,
    'tokoNama': Sesi.instance.tokoNama,
    'pesanTerimaKasih': Sesi.instance.pesanTerimaKasih,
  });

  final sebelum = _semuaHwndProsesIni();
  final controller = await WindowController.create(
      WindowConfiguration(arguments: argumen, hiddenAtLaunch: true));
  // Beri waktu proses native window (thread pesan Win32 + engine Flutter
  // barunya) benar-benar terbentuk sebelum di-enumerasi ulang.
  await Future.delayed(const Duration(milliseconds: 400));
  final sesudah = _semuaHwndProsesIni();
  final hwndBaru = sesudah.where((h) => !sebelum.contains(h)).toList();

  if (hwndBaru.isNotEmpty) {
    final hwnd = hwndBaru.first;
    _hwndLayarPelanggan = hwnd;
    try {
      await _posisikanFullscreenTanpaFrame(hwnd);
    } catch (_) {
      // Gagal deteksi monitor -- tetap tampilkan jendela apa adanya drpd gagal total.
    }
  }
  await controller.show();

  if (hwndKasir != 0) SetForegroundWindow(hwndKasir);
}

bool tutupLayarPelangganJendelaKedua() {
  final hwnd = _hwndLayarPelanggan;
  if (hwnd == null || IsWindow(hwnd) == 0) {
    _hwndLayarPelanggan = null;
    return false;
  }
  PostMessage(hwnd, WM_CLOSE, 0, 0);
  _hwndLayarPelanggan = null;
  return true;
}

Future<void> _posisikanFullscreenTanpaFrame(int hwnd,
    {int? monitorIndex}) async {
  final displays = await screenRetriever.getAllDisplays();
  final primary = await screenRetriever.getPrimaryDisplay();
  final sekunder = displays.where((d) => d.id != primary.id).toList();
  final urut = [primary, ...sekunder];
  final index = monitorIndex == null
      ? (sekunder.isNotEmpty ? 1 : 0)
      : monitorIndex.clamp(0, urut.length - 1);
  final target = urut[index];

  // Borderless fullscreen: hilangkan title bar, border, resize handle, dan
  // caption Windows. Window tetap milik proses yang sama, hanya framenya
  // dibuang supaya customer display tampil seperti kiosk.
  SetWindowLongPtr(
    hwnd,
    WINDOW_LONG_PTR_INDEX.GWL_STYLE,
    WINDOW_STYLE.WS_POPUP | WINDOW_STYLE.WS_VISIBLE,
  );

  final skala = (target.scaleFactor ?? 1).toDouble();
  final posisi = target.visiblePosition ?? Offset.zero;
  final ukuran = target.size;
  SetWindowPos(
    hwnd,
    0,
    (posisi.dx * skala).round(),
    (posisi.dy * skala).round(),
    (ukuran.width * skala).round(),
    (ukuran.height * skala).round(),
    SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED | SET_WINDOW_POS_FLAGS.SWP_SHOWWINDOW,
  );
  ShowWindow(hwnd, SHOW_WINDOW_CMD.SW_SHOWMAXIMIZED);
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
