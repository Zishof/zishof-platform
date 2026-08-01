import 'models.dart';

/// Data toko/kasir yang sedang login -- diisi sekali sesudah aksi "konfigurasi"
/// dipanggil (lihat KasirScreen.initState), dipakai layar-layar berikutnya
/// tanpa perlu meminta ulang ke server (pajak, nama toko, daftar cara bayar).
class Sesi {
  Sesi._();
  static final Sesi instance = Sesi._();

  String tokoNama = '';
  int? tokoId;
  String userId = '';
  double pajakPersen = 0;
  List<CaraBayar> caraBayar = [];
  String pesanTerimaKasih = '';
  bool wajibSesiKas = false;
  bool isAdmin = false;
  bool supervisorPedagang = false;

  /// Flag per-menu dari `konfigurasi.aksesMenu` (server, Tbmrole.ebisnisMenu) --
  /// mengontrol VISIBILITAS menu di drawer/sidebar (padanan akses-menu.js
  /// Electron). Ini murni UX; gerbang SEBENARNYA tetap ditegakkan server-side
  /// di tiap aksi. Kunci hilang = boleh (sama seperti default server `true`).
  Map<String, bool> aksesMenu = {};
  bool bolehMenu(String kunci) => aksesMenu[kunci] ?? true;

  /// Boleh mengelola (ubah/hapus/batal) -- padanan gerbang client-side yang
  /// sudah dipakai Electron/Android existing utk sembunyikan tombol destruktif
  /// dari kasir biasa (server TETAP menegakkan gerbang sungguhan di tiap aksi,
  /// ini hanya UI, lihat JavaDoc bolehSupervisorAtauAdmin di PosApi.java).
  bool get bolehKelola => isAdmin || supervisorPedagang;

  void reset() {
    tokoNama = '';
    tokoId = null;
    userId = '';
    pajakPersen = 0;
    caraBayar = [];
    pesanTerimaKasih = '';
    wajibSesiKas = false;
    isAdmin = false;
    supervisorPedagang = false;
    aksesMenu = {};
  }
}
