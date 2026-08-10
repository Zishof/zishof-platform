import 'models.dart';

/// Data toko/kasir yang sedang login -- diisi sekali sesudah aksi "konfigurasi"
/// dipanggil (lihat KasirScreen.initState), dipakai layar-layar berikutnya
/// tanpa perlu meminta ulang ke server (pajak, nama toko, daftar cara bayar).
class Sesi {
  Sesi._();
  static final Sesi instance = Sesi._();

  String tokoNama = '';
  String tokoAlamat = '';
  String tokoTelp = '';
  int? tokoId;
  String userId = '';
  double pajakPersen = 0;
  List<CaraBayar> caraBayar = [];
  String pesanTerimaKasih = '';
  bool wajibSesiKas = false;
  bool isAdmin = false;
  bool supervisorPedagang = false;

  /// Fitur "Topup" (tab Pelanggan) -- padanan `Tbmrole.bolehEntryTopup` JSP,
  /// gerbang SENDIRI (bukan turunan `bolehKelola`) krn di JSP kasir non-
  /// supervisor pun BISA diberi hak ini secara granular per-role, terpisah
  /// dari hak kelola CRUD member. Server tetap menegakkan gerbang sungguhan
  /// di `KantinHelper.topupSaldo/depositUbah/depositHapus` -- ini murni UI.
  bool bolehEntryTopup = false;

  /// Multi-toko (spec: akun boleh akses lebih dari satu toko, dipilih via
  /// `Tbmrole.tokoAksesJson`) -- `konfigurasi` sudah lama mengembalikan
  /// `multiToko`/`daftarToko`/`tokoAktifId`, hanya klien yang belum pernah
  /// menampilkan pemilihnya. `daftarToko`: List of {id, nama}.
  bool multiToko = false;
  List<Map<String, dynamic>> daftarToko = [];

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
    tokoAlamat = '';
    tokoTelp = '';
    tokoId = null;
    userId = '';
    pajakPersen = 0;
    caraBayar = [];
    pesanTerimaKasih = '';
    wajibSesiKas = false;
    isAdmin = false;
    supervisorPedagang = false;
    bolehEntryTopup = false;
    aksesMenu = {};
    multiToko = false;
    daftarToko = [];
  }
}
