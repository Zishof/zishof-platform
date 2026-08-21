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
  List<String> alasanTahan = [];
  bool wajibSesiKas = false;
  bool bolehTransaksiStokHabis = false;

  /// Hak mengubah harga pada toko aktif (kebijakan per toko di Konfigurasi >
  /// Profil Toko). Default true supaya toko yang belum mengatur -- dan server
  /// versi lama yang belum mengirim field ini -- berperilaku seperti sebelumnya.
  bool bolehUbahHarga = true;
  String pesanTidakBolehUbahHarga =
      'Anda tidak boleh mengubah harga karena tidak diberikan akses.';
  bool tokoDemo = false;
  bool dataSampleEbisnis = false;
  bool isAdmin = false;
  bool supervisorPedagang = false;

  /// Fitur "Topup" (tab Pelanggan) -- padanan `Tbmrole.bolehEntryTopup` JSP,
  /// gerbang SENDIRI (bukan turunan `bolehKelola`) krn di JSP kasir non-
  /// supervisor pun BISA diberi hak ini secara granular per-role, terpisah
  /// dari hak kelola CRUD member. Server tetap menegakkan gerbang sungguhan
  /// di `KantinHelper.topupSaldo/depositUbah/depositHapus` -- ini murni UI.
  bool bolehEntryTopup = false;
  bool bolehHapusPesanan = false;

  /// Multi-toko (spec: akun boleh akses lebih dari satu toko, dipilih via
  /// `Tbmrole.tokoAksesJson`) -- `konfigurasi` sudah lama mengembalikan
  /// `multiToko`/`daftarToko`/`tokoAktifId`, hanya klien yang belum pernah
  /// menampilkan pemilihnya. `daftarToko`: List of {id, nama}.
  bool multiToko = false;

  /// ── Filter toko lintas-toko (izin Tbmrole "Boleh melihat seluruh toko") ──
  /// [bolehSemuaToko] berasal dari server (aksi `toko_filter_list`), TIDAK
  /// disimpulkan di klien. [tokoFilter] null berarti "Semua Toko"; nilainya
  /// disisipkan ke payload Dashboard/Laporan oleh ApiClient.
  bool bolehSemuaToko = false;
  int? tokoFilter;
  List<Map<String, dynamic>> daftarTokoFilter = const [];

  String get namaTokoFilter {
    if (tokoFilter == null) return 'Semua Toko';
    for (final t in daftarTokoFilter) {
      if (t['id'] == tokoFilter) return '${t['nama'] ?? ''}';
    }
    return tokoNama;
  }

  /// Toko yang sedang DITUJU oleh layar yang mengurus SATU toko (mis. Profil
  /// Toko), berbeda dari [tokoFilter] yang hanya menyempitkan laporan.
  ///
  /// Urutannya penting. Kotak toko di kiri atas menampilkan [namaTokoFilter]
  /// bagi pengguna berizin lintas toko, jadi toko yang TERBACA di layar adalah
  /// [tokoFilter]. Kalau layar diam-diam memakai [tokoId], yang tersunting
  /// bukan toko yang tertulis di depan mata pengguna -- kesalahan yang paling
  /// mahal justru karena tidak memunculkan galat apa pun. [tokoId] dipakai
  /// sebagai cadangan untuk akun yang memang terikat ke satu toko.
  int? get idTokoTerpilih => tokoFilter ?? tokoId;

  List<Map<String, dynamic>> daftarToko = [];

  /// Flag per-menu dari `konfigurasi.aksesMenu` (server, Tbmrole.ebisnisMenu) --
  /// mengontrol VISIBILITAS menu di drawer/sidebar (padanan akses-menu.js
  /// Electron). Ini murni UX; gerbang SEBENARNYA tetap ditegakkan server-side
  /// di tiap aksi. Kunci hilang = boleh (sama seperti default server `true`).
  Map<String, bool> aksesMenu = {};
  bool bolehMenu(String kunci) => isAdmin || (aksesMenu[kunci] ?? true);

  /// CRUD granular POS biasa. Kunci/aksi lama yang belum dikirim server
  /// tetap mengikuti kompatibilitas lama (boleh), sementara server selalu
  /// menjadi gerbang keamanan yang sebenarnya.
  Map<String, Map<String, bool>> crudPos = {};
  bool bolehAksiPos(String kunci, String aksi) =>
      bolehKelola || (crudPos[kunci]?[aksi] ?? true);

  /// Gerbang menu KUNCI VARIAN BARU (apotik_/emedik_/kunci fail-closed lain di
  /// `aksesMenu`) -- KEBALIKAN [bolehMenu]: kunci hilang = TIDAK boleh.
  /// Padanan server: `EbisnisMenuKatalog.KUNCI_DEFAULT_NONAKTIF` (PosApi selalu
  /// mengirim kunci itu eksplisit; `?? false` di sini menjaga sisi klien bila
  /// server LAMA belum mengirimnya -- jangan pernah pakai [bolehMenu] untuk
  /// kunci varian baru). Admin selalu boleh.
  bool bolehMenuVarianBaru(String kunci) =>
      isAdmin || (aksesMenu[kunci] ?? false);

  // ---------------------------------------------------------------------------
  // Konteks aktor varian "eBisnis Inventory & Sales" -- dari blok ADITIF
  // `konfigurasi.aktorInventorySales` (server: EbisnisActorContextResolver,
  // fail-closed). Kosong/POS_LAINNYA utk akun POS biasa; klien varian lama
  // tidak pernah membaca field-field ini.
  // ---------------------------------------------------------------------------
  String actorType = '';
  String activeRoleId = '';
  List<String> roleIds = [];
  int? salesId;
  String salesKode = '';
  String salesNama = '';
  int? currentTripId;
  List<String> featureProfile = [];
  Map<String, bool> menuInventorySales = {};

  bool get isPemilikSalesInventory => actorType == 'PEMILIK_SALES_INVENTORY';
  bool get isSalesKeliling => actorType == 'SALES_KELILING';
  bool get isAktorInventorySales =>
      featureProfile.contains('inventory_sales') || isAdmin;

  /// Visibilitas menu varian Inventory & Sales -- BERBEDA dari [bolehMenu]:
  /// kunci hilang = TIDAK boleh (fail-closed, paritas default server
  /// `EbisnisMenuKatalog.KUNCI_DEFAULT_NONAKTIF`). Admin selalu boleh.
  bool bolehMenuIs(String kunci) =>
      isAdmin || (menuInventorySales[kunci] ?? false);

  /// Aksi granular varian IS (create/update/delete/approve/reject) -- murni
  /// gating tombol; server tetap menegakkan lewat ctx.bolehAksi. Fail-closed.
  Map<String, Map<String, bool>> crudInventorySales = {};
  bool bolehAksiIs(String kunci, String aksi) =>
      isAdmin || (crudInventorySales[kunci]?[aksi] ?? false);

  /// Boleh mengelola (ubah/hapus/batal) -- padanan gerbang client-side yang
  /// sudah dipakai Electron/Android existing utk sembunyikan tombol destruktif
  /// dari kasir biasa (server TETAP menegakkan gerbang sungguhan di tiap aksi,
  /// ini hanya UI, lihat JavaDoc bolehSupervisorAtauAdmin di PosApi.java).
  bool get bolehKelola => isAdmin || supervisorPedagang;
  bool get bolehDataSample => isAdmin && tokoDemo && dataSampleEbisnis;

  /// Terapkan balasan aksi `konfigurasi` ke sesi ini -- SATU titik pemetaan
  /// (dulu inline di `KasirScreen._terapkanKonfig`; dipindah ke sini saat
  /// varian Inventory & Sales butuh memuat konfigurasi dari landing sendiri
  /// tanpa lewat KasirScreen). Pemanggil multi-toko tetap wajib membungkusnya
  /// dgn guard toko-per-perangkat (lihat KasirScreen
  /// `_terapkanKonfigDenganGuardToko`).
  void terapkanKonfig(Map<String, dynamic> konfig) {
    tokoNama = (konfig['tokoNama'] ?? '') as String;
    tokoAlamat = '${konfig['tokoAlamat'] ?? konfig['alamat'] ?? ''}'.trim();
    tokoTelp =
        '${konfig['tokoTelp'] ?? konfig['telp'] ?? konfig['picHp'] ?? konfig['kontak'] ?? ''}'
            .trim();
    tokoId = konfig['tokoId'] as int?;
    userId = (konfig['userId'] ?? '') as String;
    pajakPersen = (konfig['pajakPersen'] as num?)?.toDouble() ?? 0;
    pesanTerimaKasih = (konfig['pesanTerimaKasih'] ?? '') as String;
    alasanTahan = ((konfig['alasanTahan'] as List?) ?? [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    wajibSesiKas = konfig['wajibSesiKas'] == true;
    bolehTransaksiStokHabis = konfig['bolehTransaksiStokHabis'] == true;
    bolehUbahHarga = konfig['bolehUbahHarga'] != false;
    final pesanHarga = '${konfig['pesanTidakBolehUbahHarga'] ?? ''}'.trim();
    if (pesanHarga.isNotEmpty) pesanTidakBolehUbahHarga = pesanHarga;
    tokoDemo = konfig['tokoDemo'] == true;
    dataSampleEbisnis = konfig['dataSampleEbisnis'] == true;
    isAdmin = konfig['isAdmin'] == true;
    supervisorPedagang = konfig['supervisorPedagang'] == true;
    bolehEntryTopup = konfig['bolehEntryTopup'] == true;
    bolehHapusPesanan = konfig['bolehHapusPesanan'] == true || bolehKelola;
    caraBayar = ((konfig['caraBayar'] as List?) ?? [])
        .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
        .toList();
    aksesMenu = ((konfig['aksesMenu'] as Map<String, dynamic>?) ?? {})
        .map((k, v) => MapEntry(k, v == true));
    final crudPosRaw = konfig['aksesMenuCrud'];
    crudPos = crudPosRaw is Map<String, dynamic>
        ? crudPosRaw.map((k, v) => MapEntry(
            k,
            v is Map<String, dynamic>
                ? v.map((aksi, nilai) => MapEntry(aksi, nilai == true))
                : <String, bool>{}))
        : {};
    multiToko = konfig['multiToko'] == true;
    daftarToko =
        ((konfig['daftarToko'] as List?) ?? []).cast<Map<String, dynamic>>();
    _terapkanAktor(konfig['aktorInventorySales']);
  }

  void _terapkanAktor(dynamic aktorRaw) {
    final aktor = aktorRaw is Map<String, dynamic> ? aktorRaw : null;
    if (aktor == null) {
      // Server lama tanpa blok aktor (belum di-deploy) -- biarkan default POS.
      actorType = '';
      return;
    }
    actorType = (aktor['actorType'] ?? '') as String;
    activeRoleId = '${aktor['activeRoleId'] ?? ''}';
    roleIds = ((aktor['roleIds'] as List?) ?? []).map((e) => '$e').toList();
    salesId =
        aktor['salesId'] is num ? (aktor['salesId'] as num).toInt() : null;
    salesKode = (aktor['salesKode'] ?? '') as String;
    salesNama = (aktor['salesNama'] ?? '') as String;
    currentTripId = aktor['currentTripId'] is num
        ? (aktor['currentTripId'] as num).toInt()
        : null;
    featureProfile =
        ((aktor['featureProfile'] as List?) ?? []).map((e) => '$e').toList();
    final izin = aktor['permissions'];
    final menuIs = izin is Map<String, dynamic> ? izin['menu'] : null;
    menuInventorySales = menuIs is Map<String, dynamic>
        ? menuIs.map((k, v) => MapEntry(k, v == true))
        : {};
    final crudIs = izin is Map<String, dynamic> ? izin['crud'] : null;
    crudInventorySales = crudIs is Map<String, dynamic>
        ? crudIs.map((k, v) => MapEntry(
            k,
            v is Map<String, dynamic>
                ? v.map((ak, av) => MapEntry(ak, av == true))
                : <String, bool>{}))
        : {};
  }

  void reset() {
    tokoNama = '';
    tokoAlamat = '';
    tokoTelp = '';
    tokoId = null;
    userId = '';
    pajakPersen = 0;
    caraBayar = [];
    pesanTerimaKasih = '';
    alasanTahan = [];
    wajibSesiKas = false;
    bolehTransaksiStokHabis = false;
    bolehUbahHarga = true;
    tokoDemo = false;
    dataSampleEbisnis = false;
    isAdmin = false;
    supervisorPedagang = false;
    bolehHapusPesanan = false;
    bolehEntryTopup = false;
    aksesMenu = {};
    crudPos = {};
    multiToko = false;
    daftarToko = [];
    actorType = '';
    activeRoleId = '';
    roleIds = [];
    salesId = null;
    salesKode = '';
    salesNama = '';
    currentTripId = null;
    featureProfile = [];
    menuInventorySales = {};
    crudInventorySales = {};
  }
}
