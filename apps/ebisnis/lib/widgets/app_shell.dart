import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import '../sesi.dart';
import '../services/pesanan_poller.dart';
import '../theme/app_colors.dart';
import 'app_drawer.dart';
import '../screens/kasir_screen.dart';
import '../screens/ringkasan_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/anggota_screen.dart';
import '../screens/produk_screen.dart';
import '../screens/stok_opname_screen.dart';
import '../screens/kulakan_screen.dart';
import '../screens/diskon_screen.dart';
import '../screens/laporan_transaksi_screen.dart';
import '../screens/retur_penjualan_screen.dart';
import '../screens/riwayat_penjualan_screen.dart';
import '../screens/riwayat_sinkronisasi_screen.dart';
import '../screens/log_error_screen.dart';
import '../screens/konfigurasi_screen.dart';
import '../screens/layar_pelanggan_screen.dart';
import '../screens/laporan_screen.dart';

/// Ambang lebar layar dianggap "desktop" (sidebar+topbar persisten spt
/// referensi) vs "mobile" (drawer+app bar ringkas, pola Material yang sudah
/// dipakai sejak awal proyek) -- 900dp dipilih krn cukup luas utk sidebar
/// 240dp + konten tanpa terasa sempit, tapi masih di bawah lebar tablet
/// landscape kecil.
const kAmbangLebarDesktop = 900.0;

/// Kunci menu, dipetakan ke label+ikon+builder layar tujuan -- dipakai
/// AppSidebar (desktop) DAN AppDrawer (mobile, lihat app_drawer.dart) supaya
/// urutan/daftar menu tetap satu sumber kebenaran.
enum MenuEBisnis { kasir, ringkasan, pesanan, anggota, produk, stokOpname, kulakan, diskon, returPenjualan, riwayatPenjualan, laporanTransaksi, laporanLaporan, riwayatSinkron, logError, konfigurasi, layarPelanggan }

class _ItemMenuShell {
  final MenuEBisnis kunci;
  final IconData icon;
  final String label;
  final bool segeraHadir;
  final WidgetBuilder? builder;
  const _ItemMenuShell(this.kunci, this.icon, this.label, {this.segeraHadir = false, this.builder});
}

/// Kunci `MenuEBisnis` -> kunci `konfigurasi.aksesMenu` server (lihat
/// PosApi.java, Tbmrole.ebisnisMenu) -- dipakai [bolehTampilMenu] utk
/// menyembunyikan item yg akunnya tak diberi akses (padanan akses-menu.js).
const _kunciAksesMenu = <MenuEBisnis, String>{
  MenuEBisnis.kasir: 'kasir',
  MenuEBisnis.ringkasan: 'ringkasan',
  MenuEBisnis.pesanan: 'pesanan',
  MenuEBisnis.anggota: 'anggota',
  MenuEBisnis.produk: 'produk',
  MenuEBisnis.stokOpname: 'stokopname',
  MenuEBisnis.kulakan: 'kulakan',
  MenuEBisnis.diskon: 'diskon',
  MenuEBisnis.returPenjualan: 'returpenjualan',
  MenuEBisnis.riwayatPenjualan: 'riwayatpenjualan',
  MenuEBisnis.laporanTransaksi: 'laporantransaksi',
  MenuEBisnis.laporanLaporan: 'laporan',
  MenuEBisnis.riwayatSinkron: 'riwayatsinkronisasi',
  MenuEBisnis.logError: 'logerror',
  MenuEBisnis.konfigurasi: 'konfigurasi',
};

bool bolehTampilMenu(MenuEBisnis kunci) {
  final kunciServer = _kunciAksesMenu[kunci];
  return kunciServer == null || Sesi.instance.bolehMenu(kunciServer);
}

const _daftarMenu = <_ItemMenuShell>[
  _ItemMenuShell(MenuEBisnis.kasir, Icons.point_of_sale, 'Kasir/POS', builder: _bangunKasir),
  _ItemMenuShell(MenuEBisnis.ringkasan, Icons.dashboard_outlined, 'Dashboard', builder: _bangunRingkasan),
  _ItemMenuShell(MenuEBisnis.pesanan, Icons.receipt_long, 'Pesanan', builder: _bangunPesanan),
  _ItemMenuShell(MenuEBisnis.anggota, Icons.people_outline, 'Pelanggan', builder: _bangunAnggota),
  _ItemMenuShell(MenuEBisnis.produk, Icons.inventory_2_outlined, 'Produk', builder: _bangunProduk),
  _ItemMenuShell(MenuEBisnis.stokOpname, Icons.fact_check_outlined, 'Stok Opname', builder: _bangunStok),
  _ItemMenuShell(MenuEBisnis.kulakan, Icons.local_shipping_outlined, 'Kulakan', builder: _bangunKulakan),
  _ItemMenuShell(MenuEBisnis.diskon, Icons.sell_outlined, 'Aturan Diskon', builder: _bangunDiskon),
  _ItemMenuShell(MenuEBisnis.returPenjualan, Icons.assignment_return_outlined, 'Retur Penjualan', builder: _bangunReturPenjualan),
  _ItemMenuShell(MenuEBisnis.riwayatPenjualan, Icons.history, 'Riwayat Penjualan', builder: _bangunRiwayatPenjualan),
  _ItemMenuShell(MenuEBisnis.laporanTransaksi, Icons.assessment_outlined, 'Laporan Transaksi', builder: _bangunLaporanTransaksi),
  _ItemMenuShell(MenuEBisnis.laporanLaporan, Icons.folder_outlined, 'Laporan-Laporan', builder: _bangunLaporanLaporan),
  _ItemMenuShell(MenuEBisnis.riwayatSinkron, Icons.sync, 'Riwayat Sinkronisasi', builder: _bangunRiwayatSinkron),
  _ItemMenuShell(MenuEBisnis.logError, Icons.error_outline, 'Log Error', builder: _bangunLogError),
  _ItemMenuShell(MenuEBisnis.konfigurasi, Icons.settings_outlined, 'Konfigurasi', builder: _bangunKonfigurasi),
  _ItemMenuShell(MenuEBisnis.layarPelanggan, Icons.desktop_windows_outlined, 'Layar Pelanggan', builder: _bangunLayarPelanggan),
];

Widget _bangunKasir(BuildContext c) => const KasirScreen();
Widget _bangunRingkasan(BuildContext c) => const RingkasanScreen();
Widget _bangunPesanan(BuildContext c) => const PesananScreen();
Widget _bangunAnggota(BuildContext c) => const AnggotaScreen();
Widget _bangunProduk(BuildContext c) => const ProdukScreen();
Widget _bangunStok(BuildContext c) => const StokOpnameScreen();
Widget _bangunKulakan(BuildContext c) => const KulakanScreen();
Widget _bangunDiskon(BuildContext c) => const DiskonScreen();
Widget _bangunReturPenjualan(BuildContext c) => const ReturPenjualanScreen();
Widget _bangunRiwayatPenjualan(BuildContext c) => const RiwayatPenjualanScreen();
Widget _bangunLaporanTransaksi(BuildContext c) => const LaporanTransaksiScreen();
Widget _bangunLaporanLaporan(BuildContext c) => const LaporanScreen();
Widget _bangunRiwayatSinkron(BuildContext c) => const RiwayatSinkronisasiScreen();
Widget _bangunLogError(BuildContext c) => const LogErrorScreen();
Widget _bangunKonfigurasi(BuildContext c) => const KonfigurasiScreen();
Widget _bangunLayarPelanggan(BuildContext c) => const LayarPelangganScreen();

void _pindahMenu(BuildContext context, _ItemMenuShell item) {
  if (item.segeraHadir || item.builder == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.label} sedang dikerjakan, menyusul di rilis berikutnya.')));
    return;
  }
  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: item.builder!));
}

/// Bungkus setiap layar yang sudah di-reskin -- lebar >= [kAmbangLebarDesktop]
/// dapat sidebar navy + topbar status persisten (padanan referensi desktop);
/// lebih sempit jatuh ke drawer + app bar ringkas (AppDrawer yang sudah ada,
/// dipakai apa adanya -- TIDAK dibuat drawer kedua, biar satu sumber
/// kebenaran menu utk mobile).
///
/// [judul]/[subjudul] mengisi header halaman (spt "Dashboard Bisnis" pada
/// referensi). [aksiHeader] utk tombol aksi khusus halaman (mis. date-range
/// picker) diletakkan di kanan header, sebaris dgn judul.
class AppShell extends StatelessWidget {
  final MenuEBisnis menuAktif;
  final String judul;
  final String? subjudul;
  final Widget? aksiHeader;
  final Widget body;
  final Widget? floatingActionButton;

  /// Kalau false, [body] mengurus scroll-nya sendiri (dibungkus Expanded,
  /// BUKAN SingleChildScrollView) -- wajib dipakai layar dgn TabBarView
  /// (butuh tinggi terbatas, konflik kalau dipaksa masuk scroll view tanpa
  /// batas tinggi).
  final bool scrollable;

  /// Bar tetap di bawah (mis. ringkasan keranjang+tombol Bayar di Kasir) --
  /// TIDAK ikut ter-scroll bersama [body].
  final Widget? bottomBar;

  /// Sembunyikan baris judul/subjudul halaman (dipakai layar spt Kasir yang
  /// di referensi langsung ke pencarian tanpa judul besar).
  final bool tampilkanJudul;

  /// Tombol aksi di AppBar mobile (mis. sync/refresh/logout) -- di desktop,
  /// [aksiHeader] yang dipakai utk slot setara.
  final List<Widget>? actionsAppBar;

  const AppShell({
    super.key,
    required this.menuAktif,
    required this.judul,
    this.subjudul,
    this.aksiHeader,
    required this.body,
    this.floatingActionButton,
    this.scrollable = true,
    this.bottomBar,
    this.tampilkanJudul = true,
    this.actionsAppBar,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= kAmbangLebarDesktop;
      if (!desktop) {
        return Scaffold(
          backgroundColor: AppColors.pageBg,
          appBar: AppBar(title: Text(judul), backgroundColor: AppColors.sidebarBg, foregroundColor: Colors.white, actions: actionsAppBar),
          drawer: const AppDrawer(),
          floatingActionButton: floatingActionButton,
          body: body,
          bottomNavigationBar: bottomBar,
        );
      }
      return Scaffold(
        backgroundColor: AppColors.pageBg,
        floatingActionButton: floatingActionButton,
        body: Row(
          children: [
            _AppSidebar(menuAktif: menuAktif),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AppTopbar(),
                  if (tampilkanJudul)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(judul, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                if (subjudul != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subjudul!, style: const TextStyle(color: AppColors.textSecondary))),
                              ],
                            ),
                          ),
                          if (aksiHeader != null) aksiHeader!,
                        ],
                      ),
                    )
                  else if (aksiHeader != null)
                    // Layar spt Kasir sembunyikan judul besar (langsung ke pencarian), TAPI
                    // aksiHeader (mis. toolbar Akun Saya/Layar Pelanggan/Buka Laci/Ganti Toko)
                    // tetap wajib tampil -- gap-closure: sebelumnya baris ini terlewat total
                    // kalau tampilkanJudul false, jadi tombol2 toolbar itu ada di kode tapi tak
                    // pernah ter-render sama sekali di desktop.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Align(alignment: Alignment.centerRight, child: aksiHeader!),
                    ),
                  Expanded(
                    child: scrollable
                        ? SingleChildScrollView(padding: const EdgeInsets.all(24), child: body)
                        : Padding(padding: EdgeInsets.fromLTRB(24, tampilkanJudul ? 12 : 20, 24, 0), child: body),
                  ),
                  if (bottomBar != null) bottomBar!,
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _AppSidebar extends StatelessWidget {
  final MenuEBisnis menuAktif;
  const _AppSidebar({required this.menuAktif});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppColors.sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                children: [
                  Icon(Icons.link, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text('eBisnis POS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _daftarMenu.where((item) => bolehTampilMenu(item.kunci)).map((item) {
                  final aktif = item.kunci == menuAktif;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    child: Material(
                      color: aktif ? AppColors.sidebarBgActive : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _pindahMenu(context, item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          child: Row(
                            children: [
                              item.kunci == MenuEBisnis.pesanan
                                  ? ValueListenableBuilder<int>(
                                      valueListenable: PesananPoller.instance.jumlahBaru,
                                      builder: (context, jumlah, _) => Badge(
                                        label: Text('$jumlah'),
                                        isLabelVisible: jumlah > 0,
                                        child: Icon(item.icon, size: 19, color: aktif ? AppColors.sidebarTextActive : AppColors.sidebarText),
                                      ),
                                    )
                                  : Icon(item.icon, size: 19, color: aktif ? AppColors.sidebarTextActive : AppColors.sidebarText),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(item.label,
                                    style: TextStyle(color: aktif ? AppColors.sidebarTextActive : AppColors.sidebarText, fontSize: 13, fontWeight: aktif ? FontWeight.w600 : FontWeight.normal)),
                              ),
                              if (item.segeraHadir) const Icon(Icons.lock_clock_outlined, size: 14, color: AppColors.sidebarText),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTopbar extends StatefulWidget {
  const _AppTopbar();
  @override
  State<_AppTopbar> createState() => _AppTopbarState();
}

class _AppTopbarState extends State<_AppTopbar> {
  Map<String, Object?>? _kasAktif;
  int _pendingSync = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final kas = await CoreDb.instance.sesiKasAktif();
    final pending = await CoreDb.instance.jumlahTransaksiPending();
    if (mounted) {
      setState(() {
        _kasAktif = kas;
        _pendingSync = pending;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kasTerbuka = _kasAktif != null;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          const Icon(Icons.storefront_outlined, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 6),
          Text(Sesi.instance.tokoNama.isEmpty ? 'eBisnis' : Sesi.instance.tokoNama, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const Spacer(),
          _chipStatus(
            icon: Icons.point_of_sale_outlined,
            label: kasTerbuka ? 'Kas Terbuka' : 'Kas Tertutup',
            warna: kasTerbuka ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          _chipStatus(
            icon: _pendingSync == 0 ? Icons.cloud_done_outlined : Icons.cloud_sync_outlined,
            label: _pendingSync == 0 ? 'Sync Online' : '$_pendingSync Tertunda',
            warna: _pendingSync == 0 ? AppColors.teal : AppColors.warning,
          ),
          const SizedBox(width: 16),
          CircleAvatar(radius: 16, backgroundColor: AppColors.primary, child: Text(Sesi.instance.userId.isNotEmpty ? Sesi.instance.userId[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 13))),
          const SizedBox(width: 8),
          Text(Sesi.instance.userId, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _chipStatus({required IconData icon, required String label, required Color warna}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.latarLembut(warna), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: warna),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: warna)),
        ],
      ),
    );
  }
}
