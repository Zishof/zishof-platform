import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import '../api_client.dart';
import '../app_variant.dart';
import '../sesi.dart';
import '../services/pesanan_poller.dart';
import '../services/layar_pelanggan_launcher.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_drawer.dart';
import '../screens/akun_saya_screen.dart';
import '../screens/kasir_screen.dart';
import '../screens/ringkasan_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/anggota_screen.dart';
import '../screens/produk_screen.dart';
import '../screens/stok_opname_screen.dart';
import '../screens/mutasi_antar_outlet_screen.dart';
import '../screens/kulakan_screen.dart';
import '../screens/diskon_screen.dart';
import '../screens/cara_bayar_screen.dart';
import '../screens/jenis_produk_screen.dart';
import '../screens/laporan_transaksi_screen.dart';
import '../screens/retur_penjualan_screen.dart';
import '../screens/riwayat_penjualan_screen.dart';
import '../screens/riwayat_sinkronisasi_screen.dart';
import '../screens/log_error_screen.dart';
import '../screens/konfigurasi_screen.dart';
import '../screens/layar_pelanggan_screen.dart';
import '../screens/laporan_screen.dart';
import '../screens/hak_akses_screen.dart';
import '../screens/login_screen.dart';
import '../screens/inventory_sales/beranda_is_screen.dart';
import '../screens/inventory_sales/master_supplier_screen.dart';
import '../screens/inventory_sales/master_customer_screen.dart';
import '../screens/inventory_sales/master_sales_screen.dart';
import '../screens/inventory_sales/persediaan_screen.dart';
import '../screens/inventory_sales/harga_screen.dart';
import '../screens/inventory_sales/hutang_supplier_screen.dart';
import '../screens/inventory_sales/penjualan_sales_screen.dart';
import '../screens/inventory_sales/piutang_screen.dart';
import '../screens/inventory_sales/spj_screen.dart';
import '../screens/inventory_sales/nota_sales_screen.dart';
import '../screens/inventory_sales/kas_jurnal_screen.dart';
import '../screens/inventory_sales/laba_rugi_screen.dart';
import '../product_profile.dart';
import 'safe_state.dart';

/// Ambang lebar layar dianggap "desktop" (sidebar+topbar persisten spt
/// referensi) vs "mobile" (drawer+app bar ringkas, pola Material yang sudah
/// dipakai sejak awal proyek) -- 900dp dipilih krn cukup luas utk sidebar
/// 240dp + konten tanpa terasa sempit, tapi masih di bawah lebar tablet
/// landscape kecil.
const kAmbangLebarDesktop = 900.0;

final _menuAktifNotifier = ValueNotifier<MenuEBisnis>(
    AppProductProfile.aktif.isInventorySales
        ? MenuEBisnis.berandaInventorySales
        : MenuEBisnis.kasir);

/// Kunci menu, dipetakan ke label+ikon+builder layar tujuan -- dipakai
/// AppSidebar (desktop) DAN AppDrawer (mobile, lihat app_drawer.dart) supaya
/// urutan/daftar menu tetap satu sumber kebenaran.
enum MenuEBisnis {
  kasir,
  ringkasan,
  pesanan,
  anggota,
  produk,
  jenisProduk,
  stokOpname,
  mutasiAntarOutlet,
  kulakan,
  diskon,
  caraBayar,
  returPenjualan,
  riwayatPenjualan,
  laporanTransaksi,
  laporanLaporan,
  laporanKeuangan,
  riwayatSinkron,
  logError,
  konfigurasi,
  layarPelanggan,
  hakAkses,
  berandaInventorySales,
  masterSupplier,
  masterCustomer,
  masterSales,
  persediaan,
  harga,
  hutangSupplier,
  penjualanSales,
  piutang,
  suratPerintahSales,
  notaSales,
  kasJurnal,
  labaRugi
}

/// Kunci menu server varian Inventory & Sales per MenuEBisnis (fail-closed --
/// dipakai [bolehTampilMenu] lewat `Sesi.bolehMenuIs`, kunci hilang = sembunyi).
const _kunciMenuIs = <MenuEBisnis, String>{
  MenuEBisnis.masterSupplier: 'master_supplier',
  MenuEBisnis.masterCustomer: 'master_customer',
  MenuEBisnis.masterSales: 'master_sales',
  MenuEBisnis.persediaan: 'persediaan',
  MenuEBisnis.harga: 'harga',
  MenuEBisnis.hutangSupplier: 'hutang',
  MenuEBisnis.penjualanSales: 'penjualan_sales',
  MenuEBisnis.piutang: 'piutang',
  MenuEBisnis.suratPerintahSales: 'surat_perintah_sales',
  MenuEBisnis.notaSales: 'nota_sales',
  MenuEBisnis.kasJurnal: 'kas_jurnal',
  MenuEBisnis.labaRugi: 'laba_rugi',
};

class _ItemMenuShell {
  final MenuEBisnis kunci;
  final IconData icon;
  final String label;
  final WidgetBuilder? builder;
  const _ItemMenuShell(this.kunci, this.icon, this.label, {this.builder});
}

class _GrupMenuShell {
  final String label;
  final List<MenuEBisnis> items;
  const _GrupMenuShell(this.label, this.items);
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
  MenuEBisnis.jenisProduk: 'produk',
  MenuEBisnis.stokOpname: 'stokopname',
  MenuEBisnis.mutasiAntarOutlet: 'mutasistokantaroutlet',
  MenuEBisnis.kulakan: 'kulakan',
  MenuEBisnis.diskon: 'diskon',
  MenuEBisnis.caraBayar: 'pembayaran',
  MenuEBisnis.returPenjualan: 'returpenjualan',
  MenuEBisnis.riwayatPenjualan: 'riwayatpenjualan',
  MenuEBisnis.laporanTransaksi: 'laporantransaksi',
  MenuEBisnis.laporanLaporan: 'laporan',
  MenuEBisnis.laporanKeuangan: 'laporankeuangan',
  MenuEBisnis.riwayatSinkron: 'riwayatsinkronisasi',
  MenuEBisnis.logError: 'logerror',
  MenuEBisnis.konfigurasi: 'konfigurasi',
};

bool bolehTampilMenu(MenuEBisnis kunci) {
  if (kunci == MenuEBisnis.hakAkses) return Sesi.instance.isAdmin;
  // Menu khusus varian "eBisnis Inventory & Sales" -- gerbang level VARIAN
  // (bukan role): tidak pernah dirakit ke sidebar varian POS lama.
  if (kunci == MenuEBisnis.berandaInventorySales) {
    return AppProductProfile.aktif.isInventorySales;
  }
  final kunciIs = _kunciMenuIs[kunci];
  if (kunciIs != null) {
    return AppProductProfile.aktif.isInventorySales &&
        Sesi.instance.bolehMenuIs(kunciIs);
  }
  final kunciServer = _kunciAksesMenu[kunci];
  return kunciServer == null || Sesi.instance.bolehMenu(kunciServer);
}

const _daftarMenu = <_ItemMenuShell>[
  _ItemMenuShell(MenuEBisnis.berandaInventorySales, Icons.storefront_outlined,
      'Beranda Inventory & Sales',
      builder: _bangunBerandaIS),
  _ItemMenuShell(MenuEBisnis.masterSupplier, Icons.local_shipping_outlined,
      'Master Supplier',
      builder: _bangunMasterSupplier),
  _ItemMenuShell(MenuEBisnis.masterCustomer, Icons.people_alt_outlined,
      'Master Customer',
      builder: _bangunMasterCustomer),
  _ItemMenuShell(MenuEBisnis.masterSales, Icons.badge_outlined, 'Master Sales',
      builder: _bangunMasterSales),
  _ItemMenuShell(MenuEBisnis.persediaan, Icons.warehouse_outlined,
      'Persediaan & Kartu Stok',
      builder: _bangunPersediaan),
  _ItemMenuShell(MenuEBisnis.harga, Icons.price_change_outlined,
      'Master & Analisis Harga',
      builder: _bangunHarga),
  _ItemMenuShell(MenuEBisnis.hutangSupplier, Icons.account_balance_outlined,
      'Hutang Supplier (AP)',
      builder: _bangunHutangSupplier),
  _ItemMenuShell(MenuEBisnis.penjualanSales, Icons.shopping_cart_checkout,
      'Penjualan Sales',
      builder: _bangunPenjualanSales),
  _ItemMenuShell(MenuEBisnis.piutang, Icons.request_quote_outlined,
      'Piutang Customer (AR)',
      builder: _bangunPiutang),
  _ItemMenuShell(MenuEBisnis.suratPerintahSales, Icons.assignment_outlined,
      'Surat Perintah Sales',
      builder: _bangunSpj),
  _ItemMenuShell(MenuEBisnis.notaSales, Icons.route_outlined,
      'Sesi Nota Sales',
      builder: _bangunNotaSales),
  _ItemMenuShell(MenuEBisnis.kasJurnal, Icons.menu_book_outlined,
      'Kas & Jurnal',
      builder: _bangunKasJurnal),
  _ItemMenuShell(MenuEBisnis.labaRugi, Icons.stacked_line_chart,
      'Laba Rugi',
      builder: _bangunLabaRugi),
  _ItemMenuShell(MenuEBisnis.kasir, Icons.point_of_sale, 'Kasir/POS',
      builder: _bangunKasir),
  _ItemMenuShell(MenuEBisnis.ringkasan, Icons.dashboard_outlined, 'Dashboard',
      builder: _bangunRingkasan),
  _ItemMenuShell(MenuEBisnis.pesanan, Icons.receipt_long, 'Pesanan',
      builder: _bangunPesanan),
  _ItemMenuShell(MenuEBisnis.anggota, Icons.people_outline, 'Pelanggan',
      builder: _bangunAnggota),
  _ItemMenuShell(MenuEBisnis.produk, Icons.inventory_2_outlined, 'Produk',
      builder: _bangunProduk),
  _ItemMenuShell(MenuEBisnis.jenisProduk, Icons.category_outlined,
      'Jenis Produk',
      builder: _bangunJenisProduk),
  _ItemMenuShell(
      MenuEBisnis.stokOpname, Icons.fact_check_outlined, 'Stok Opname',
      builder: _bangunStok),
  _ItemMenuShell(MenuEBisnis.mutasiAntarOutlet, Icons.compare_arrows,
      'Mutasi Antar Outlet',
      builder: _bangunMutasiAntarOutlet),
  _ItemMenuShell(MenuEBisnis.kulakan, Icons.local_shipping_outlined, 'Kulakan',
      builder: _bangunKulakan),
  _ItemMenuShell(MenuEBisnis.diskon, Icons.sell_outlined, 'Aturan Diskon',
      builder: _bangunDiskon),
  _ItemMenuShell(MenuEBisnis.caraBayar, Icons.payments_outlined,
      'Cara Pembayaran',
      builder: _bangunCaraBayar),
  _ItemMenuShell(MenuEBisnis.returPenjualan, Icons.assignment_return_outlined,
      'Retur Penjualan',
      builder: _bangunReturPenjualan),
  _ItemMenuShell(
      MenuEBisnis.riwayatPenjualan, Icons.history, 'Riwayat Penjualan',
      builder: _bangunRiwayatPenjualan),
  _ItemMenuShell(MenuEBisnis.laporanTransaksi, Icons.assessment_outlined,
      'Laporan Transaksi',
      builder: _bangunLaporanTransaksi),
  _ItemMenuShell(
      MenuEBisnis.laporanLaporan, Icons.folder_outlined, 'Laporan-Laporan',
      builder: _bangunLaporanLaporan),
  _ItemMenuShell(MenuEBisnis.laporanKeuangan, Icons.account_balance_outlined,
      'Laporan Keuangan',
      builder: _bangunLaporanKeuangan),
  _ItemMenuShell(MenuEBisnis.riwayatSinkron, Icons.sync, 'Riwayat Sinkronisasi',
      builder: _bangunRiwayatSinkron),
  _ItemMenuShell(MenuEBisnis.logError, Icons.error_outline, 'Log Error',
      builder: _bangunLogError),
  _ItemMenuShell(
      MenuEBisnis.konfigurasi, Icons.settings_outlined, 'Konfigurasi',
      builder: _bangunKonfigurasi),
  _ItemMenuShell(MenuEBisnis.layarPelanggan, Icons.desktop_windows_outlined,
      'Layar Pelanggan',
      builder: _bangunLayarPelanggan),
  _ItemMenuShell(
      MenuEBisnis.hakAkses, Icons.admin_panel_settings_outlined, 'Hak Akses',
      builder: _bangunHakAkses),
];

const _grupMenu = <_GrupMenuShell>[
  _GrupMenuShell('Inventory & Sales', [
    MenuEBisnis.berandaInventorySales,
    MenuEBisnis.masterSupplier,
    MenuEBisnis.masterCustomer,
    MenuEBisnis.masterSales,
    MenuEBisnis.persediaan,
    MenuEBisnis.harga,
    MenuEBisnis.hutangSupplier,
    MenuEBisnis.penjualanSales,
    MenuEBisnis.piutang,
    MenuEBisnis.suratPerintahSales,
    MenuEBisnis.notaSales,
    MenuEBisnis.kasJurnal,
    MenuEBisnis.labaRugi,
  ]),
  _GrupMenuShell('Operasional', [
    MenuEBisnis.kasir,
    MenuEBisnis.pesanan,
    MenuEBisnis.layarPelanggan,
  ]),
  _GrupMenuShell('Dashboard', [
    MenuEBisnis.ringkasan,
  ]),
  _GrupMenuShell('Master Data', [
    MenuEBisnis.anggota,
    MenuEBisnis.produk,
    MenuEBisnis.jenisProduk,
    MenuEBisnis.stokOpname,
    MenuEBisnis.mutasiAntarOutlet,
    MenuEBisnis.kulakan,
    MenuEBisnis.diskon,
    MenuEBisnis.caraBayar,
  ]),
  _GrupMenuShell('Transaksi & Laporan', [
    MenuEBisnis.returPenjualan,
    MenuEBisnis.riwayatPenjualan,
    MenuEBisnis.laporanTransaksi,
    MenuEBisnis.laporanLaporan,
    MenuEBisnis.laporanKeuangan,
  ]),
  _GrupMenuShell('Sistem', [
    MenuEBisnis.riwayatSinkron,
    MenuEBisnis.logError,
    MenuEBisnis.konfigurasi,
    MenuEBisnis.hakAkses,
  ]),
];

Widget _bangunKasir(BuildContext c) => const KasirScreen();
Widget _bangunRingkasan(BuildContext c) => const RingkasanScreen();
Widget _bangunPesanan(BuildContext c) => const PesananScreen();
Widget _bangunAnggota(BuildContext c) => const AnggotaScreen();
Widget _bangunProduk(BuildContext c) => const ProdukScreen();
Widget _bangunJenisProduk(BuildContext c) => const JenisProdukScreen();
Widget _bangunStok(BuildContext c) => const StokOpnameScreen();
Widget _bangunMutasiAntarOutlet(BuildContext c) =>
    const MutasiAntarOutletScreen();
Widget _bangunKulakan(BuildContext c) => const KulakanScreen();
Widget _bangunDiskon(BuildContext c) => const DiskonScreen();
Widget _bangunCaraBayar(BuildContext c) => const CaraBayarScreen();
Widget _bangunReturPenjualan(BuildContext c) => const ReturPenjualanScreen();
Widget _bangunRiwayatPenjualan(BuildContext c) =>
    const RiwayatPenjualanScreen();
Widget _bangunLaporanTransaksi(BuildContext c) =>
    const LaporanTransaksiScreen();
Widget _bangunLaporanLaporan(BuildContext c) => const LaporanScreen();
Widget _bangunLaporanKeuangan(BuildContext c) => const LaporanScreen(
      aksiKatalog: 'laporan_keuangan_katalog',
      menuAktif: MenuEBisnis.laporanKeuangan,
      judul: 'Laporan Keuangan',
      subjudul: 'Neraca, Laba Rugi, Arus Kas, Buku Besar, Piutang & lainnya',
    );
Widget _bangunRiwayatSinkron(BuildContext c) =>
    const RiwayatSinkronisasiScreen();
Widget _bangunLogError(BuildContext c) => const LogErrorScreen();
Widget _bangunKonfigurasi(BuildContext c) => const KonfigurasiScreen();
Widget _bangunLayarPelanggan(BuildContext c) => const LayarPelangganScreen();
Widget _bangunHakAkses(BuildContext c) => const HakAksesScreen();
Widget _bangunBerandaIS(BuildContext c) => const BerandaInventorySalesScreen();
Widget _bangunMasterSupplier(BuildContext c) => const MasterSupplierScreen();
Widget _bangunMasterCustomer(BuildContext c) => const MasterCustomerScreen();
Widget _bangunMasterSales(BuildContext c) => const MasterSalesScreen();
Widget _bangunPersediaan(BuildContext c) => const PersediaanScreen();
Widget _bangunHarga(BuildContext c) => const HargaScreen();
Widget _bangunHutangSupplier(BuildContext c) => const HutangSupplierScreen();
Widget _bangunPenjualanSales(BuildContext c) => const PenjualanSalesScreen();
Widget _bangunPiutang(BuildContext c) => const PiutangScreen();
Widget _bangunSpj(BuildContext c) => const SpjScreen();
Widget _bangunNotaSales(BuildContext c) => const NotaSalesScreen();
Widget _bangunKasJurnal(BuildContext c) => const KasJurnalScreen();
Widget _bangunLabaRugi(BuildContext c) => const LabaRugiScreen();

_ItemMenuShell? _itemMenu(MenuEBisnis kunci) {
  for (final item in _daftarMenu) {
    if (item.kunci == kunci) return item;
  }
  return null;
}

_ItemMenuShell? _itemMenuDariLabel(String label) {
  final menu = _menuDariLabel(label);
  return menu == null ? null : _itemMenu(menu);
}

void _pindahMenu(BuildContext context, _ItemMenuShell item,
    {MenuEBisnis? menuSaatIni}) {
  if (item.kunci == MenuEBisnis.layarPelanggan) {
    bukaLayarPelanggan(context);
    return;
  }
  if (item.builder == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${item.label} sedang dikerjakan, menyusul di rilis berikutnya.')));
    return;
  }
  if (item.kunci == menuSaatIni || item.kunci == _menuAktifNotifier.value) {
    return;
  }
  AppDrawer.menuAktifNotifier.value = _labelDrawer(item.kunci);
  _menuAktifNotifier.value = item.kunci;
}

String _labelDrawer(MenuEBisnis kunci) {
  switch (kunci) {
    case MenuEBisnis.kasir:
      return 'Kasir';
    case MenuEBisnis.ringkasan:
      return 'Ringkasan';
    case MenuEBisnis.pesanan:
      return 'Pesanan';
    case MenuEBisnis.anggota:
      return 'Customer/Anggota';
    case MenuEBisnis.produk:
      return 'Produk';
    case MenuEBisnis.jenisProduk:
      return 'Jenis Produk';
    case MenuEBisnis.stokOpname:
      return 'Stok Opname';
    case MenuEBisnis.mutasiAntarOutlet:
      return 'Mutasi Antar Outlet';
    case MenuEBisnis.kulakan:
      return 'Kulakan';
    case MenuEBisnis.diskon:
      return 'Aturan Diskon';
    case MenuEBisnis.caraBayar:
      return 'Cara Pembayaran';
    case MenuEBisnis.returPenjualan:
      return 'Retur Penjualan';
    case MenuEBisnis.riwayatPenjualan:
      return 'Riwayat Penjualan';
    case MenuEBisnis.laporanTransaksi:
      return 'Laporan Transaksi';
    case MenuEBisnis.laporanLaporan:
      return 'Laporan-Laporan';
    case MenuEBisnis.laporanKeuangan:
      return 'Laporan Keuangan';
    case MenuEBisnis.riwayatSinkron:
      return 'Riwayat Sinkronisasi';
    case MenuEBisnis.logError:
      return 'Log Error';
    case MenuEBisnis.konfigurasi:
      return 'Konfigurasi';
    case MenuEBisnis.layarPelanggan:
      return 'Layar Pelanggan';
    case MenuEBisnis.hakAkses:
      return 'Hak Akses';
    case MenuEBisnis.berandaInventorySales:
      return 'Beranda Inventory & Sales';
    case MenuEBisnis.masterSupplier:
      return 'Master Supplier';
    case MenuEBisnis.masterCustomer:
      return 'Master Customer';
    case MenuEBisnis.masterSales:
      return 'Master Sales';
    case MenuEBisnis.persediaan:
      return 'Persediaan & Kartu Stok';
    case MenuEBisnis.harga:
      return 'Master & Analisis Harga';
    case MenuEBisnis.hutangSupplier:
      return 'Hutang Supplier (AP)';
    case MenuEBisnis.penjualanSales:
      return 'Penjualan Sales';
    case MenuEBisnis.piutang:
      return 'Piutang Customer (AR)';
    case MenuEBisnis.suratPerintahSales:
      return 'Surat Perintah Sales';
    case MenuEBisnis.notaSales:
      return 'Sesi Nota Sales';
    case MenuEBisnis.kasJurnal:
      return 'Kas & Jurnal';
    case MenuEBisnis.labaRugi:
      return 'Laba Rugi';
  }
}

MenuEBisnis? _menuDariLabel(String label) {
  switch (label) {
    case 'Kasir':
      return MenuEBisnis.kasir;
    case 'Ringkasan':
      return MenuEBisnis.ringkasan;
    case 'Pesanan':
      return MenuEBisnis.pesanan;
    case 'Customer/Anggota':
      return MenuEBisnis.anggota;
    case 'Produk':
      return MenuEBisnis.produk;
    case 'Jenis Produk':
      return MenuEBisnis.jenisProduk;
    case 'Stok Opname':
      return MenuEBisnis.stokOpname;
    case 'Mutasi Antar Outlet':
      return MenuEBisnis.mutasiAntarOutlet;
    case 'Kulakan':
      return MenuEBisnis.kulakan;
    case 'Aturan Diskon':
      return MenuEBisnis.diskon;
    case 'Cara Pembayaran':
      return MenuEBisnis.caraBayar;
    case 'Retur Penjualan':
      return MenuEBisnis.returPenjualan;
    case 'Riwayat Penjualan':
      return MenuEBisnis.riwayatPenjualan;
    case 'Laporan Transaksi':
      return MenuEBisnis.laporanTransaksi;
    case 'Laporan-Laporan':
      return MenuEBisnis.laporanLaporan;
    case 'Laporan Keuangan':
      return MenuEBisnis.laporanKeuangan;
    case 'Riwayat Sinkronisasi':
      return MenuEBisnis.riwayatSinkron;
    case 'Log Error':
      return MenuEBisnis.logError;
    case 'Konfigurasi':
      return MenuEBisnis.konfigurasi;
    case 'Layar Pelanggan':
      return MenuEBisnis.layarPelanggan;
    case 'Hak Akses':
      return MenuEBisnis.hakAkses;
    case 'Beranda Inventory & Sales':
      return MenuEBisnis.berandaInventorySales;
    case 'Master Supplier':
      return MenuEBisnis.masterSupplier;
    case 'Master Customer':
      return MenuEBisnis.masterCustomer;
    case 'Master Sales':
      return MenuEBisnis.masterSales;
    case 'Persediaan & Kartu Stok':
      return MenuEBisnis.persediaan;
    case 'Master & Analisis Harga':
      return MenuEBisnis.harga;
    case 'Hutang Supplier (AP)':
      return MenuEBisnis.hutangSupplier;
    case 'Penjualan Sales':
      return MenuEBisnis.penjualanSales;
    case 'Piutang Customer (AR)':
      return MenuEBisnis.piutang;
    case 'Surat Perintah Sales':
      return MenuEBisnis.suratPerintahSales;
    case 'Sesi Nota Sales':
      return MenuEBisnis.notaSales;
    case 'Kas & Jurnal':
      return MenuEBisnis.kasJurnal;
    case 'Laba Rugi':
      return MenuEBisnis.labaRugi;
  }
  return null;
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
class AppShell extends StatefulWidget {
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
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _notifierSudahSinkron = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_menuAktifNotifier.value != widget.menuAktif) {
        _menuAktifNotifier.value = widget.menuAktif;
      }
      AppDrawer.menuAktifNotifier.value = _labelDrawer(widget.menuAktif);
      if (mounted) {
        setStateIfMounted(() => _notifierSudahSinkron = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MenuEBisnis>(
      valueListenable: _menuAktifNotifier,
      builder: (context, menuTerpilih, _) {
        if (_notifierSudahSinkron && menuTerpilih != widget.menuAktif) {
          final item = _itemMenu(menuTerpilih);
          if (item?.builder != null) return item!.builder!(context);
        }
        return _buildShell(context);
      },
    );
  }

  Widget _buildShell(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= kAmbangLebarDesktop;
      if (!desktop) {
        return Scaffold(
          backgroundColor: AppColors.pageBgOf(context),
          appBar: AppBar(
              title: Text(widget.judul),
              backgroundColor: AppColors.sidebarBg,
              foregroundColor: Colors.white,
              actions: widget.actionsAppBar),
          drawer: AppDrawer(
            menuAktif: _labelDrawer(widget.menuAktif),
            onPilihMenu: (label) {
              final item = _itemMenuDariLabel(label);
              if (item != null) {
                _pindahMenu(context, item, menuSaatIni: widget.menuAktif);
              }
            },
          ),
          floatingActionButton: widget.floatingActionButton,
          body: widget.body,
          bottomNavigationBar: widget.bottomBar,
        );
      }
      return Scaffold(
        backgroundColor: AppColors.pageBgOf(context),
        floatingActionButton: widget.floatingActionButton,
        body: Row(
          children: [
            _AppSidebar(menuAktif: widget.menuAktif),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AppTopbar(),
                  if (widget.tampilkanJudul)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.judul,
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            AppColors.textPrimaryOf(context))),
                                if (widget.subjudul != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(widget.subjudul!,
                                          style: TextStyle(
                                              color: AppColors.textSecondaryOf(
                                                  context)))),
                              ],
                            ),
                          ),
                          if (widget.aksiHeader != null) widget.aksiHeader!,
                        ],
                      ),
                    )
                  else if (widget.aksiHeader != null)
                    // Layar spt Kasir sembunyikan judul besar (langsung ke pencarian), TAPI
                    // aksiHeader (mis. toolbar Akun Saya/Layar Pelanggan/Buka Laci/Ganti Toko)
                    // tetap wajib tampil -- gap-closure: sebelumnya baris ini terlewat total
                    // kalau tampilkanJudul false, jadi tombol2 toolbar itu ada di kode tapi tak
                    // pernah ter-render sama sekali di desktop.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: widget.aksiHeader!),
                    ),
                  Expanded(
                    child: widget.scrollable
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: widget.body)
                        : Padding(
                            padding: EdgeInsets.fromLTRB(
                                24, widget.tampilkanJudul ? 12 : 20, 24, 0),
                            child: widget.body),
                  ),
                  if (widget.bottomBar != null) widget.bottomBar!,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                children: [
                  const Icon(Icons.link, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Text(AppVariant.namaSidebar,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                children: [
                  for (final grup in _grupMenu)
                    _SidebarGroup(grup: grup, menuAktif: menuAktif),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarGroup extends StatelessWidget {
  final _GrupMenuShell grup;
  final MenuEBisnis menuAktif;
  const _SidebarGroup({required this.grup, required this.menuAktif});

  @override
  Widget build(BuildContext context) {
    final items = grup.items
        .map(_itemMenu)
        .whereType<_ItemMenuShell>()
        .where((item) => bolehTampilMenu(item.kunci))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 12, 7),
            child: Text(
              grup.label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.sidebarText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...items.map((item) => _SidebarItem(
                item: item,
                aktif: item.kunci == menuAktif,
                menuAktif: menuAktif,
              )),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _ItemMenuShell item;
  final bool aktif;
  final MenuEBisnis menuAktif;
  const _SidebarItem({
    required this.item,
    required this.aktif,
    required this.menuAktif,
  });

  @override
  Widget build(BuildContext context) {
    final warna = aktif ? AppColors.sidebarTextActive : AppColors.sidebarText;
    final icon = Icon(item.icon, size: 19, color: warna);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: aktif ? AppColors.sidebarBgActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pindahMenu(context, item, menuSaatIni: menuAktif),
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
                          child: icon,
                        ),
                      )
                    : icon,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: warna,
                      fontSize: 13,
                      fontWeight: aktif ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                if (item.builder == null)
                  const Icon(Icons.lock_clock_outlined,
                      size: 14, color: AppColors.sidebarText),
              ],
            ),
          ),
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
    CoreDb.instance.sesiKasVersi.addListener(_muat);
    _muat();
  }

  @override
  void dispose() {
    CoreDb.instance.sesiKasVersi.removeListener(_muat);
    super.dispose();
  }

  Future<void> _muat() async {
    final kas = await CoreDb.instance.sesiKasAktif();
    final pending = await CoreDb.instance.jumlahTransaksiPending();
    if (mounted) {
      setStateIfMounted(() {
        _kasAktif = kas;
        _pendingSync = pending;
      });
    }
  }

  Future<void> _logout() async {
    await ApiClient.instance.hapusToken();
    Sesi.instance.reset();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final kasTerbuka = _kasAktif != null;
    final tampilkanStatusKas = Sesi.instance.wajibSesiKas || kasTerbuka;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined,
              color: AppColors.textSecondaryOf(context), size: 18),
          const SizedBox(width: 6),
          Text(
              Sesi.instance.tokoNama.isEmpty
                  ? AppVariant.namaAplikasi
                  : Sesi.instance.tokoNama,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryOf(context))),
          const Spacer(),
          if (tampilkanStatusKas) ...[
            _chipStatus(
              icon: Icons.point_of_sale_outlined,
              label: kasTerbuka ? 'Kas Terbuka' : 'Kas Tertutup',
              warna: kasTerbuka
                  ? AppColors.success
                  : AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: 10),
          ],
          _chipStatus(
            icon: _pendingSync == 0
                ? Icons.cloud_done_outlined
                : Icons.cloud_sync_outlined,
            label: _pendingSync == 0 ? 'Sync Online' : '$_pendingSync Tertunda',
            warna: _pendingSync == 0 ? AppColors.teal : AppColors.warning,
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Segarkan Status',
            icon: const Icon(Icons.refresh, size: 19),
            onPressed: _muat,
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppThemeController.instance.mode,
            builder: (context, mode, _) => IconButton(
              tooltip: mode == ThemeMode.dark ? 'Mode Terang' : 'Mode Gelap',
              icon: Icon(mode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined),
              onPressed: AppThemeController.instance.toggle,
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Menu Akun',
            onSelected: (value) {
              switch (value) {
                case 'akun':
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AkunSayaScreen()));
                  break;
                case 'konfigurasi':
                  _pindahMenu(context, _itemMenu(MenuEBisnis.konfigurasi)!);
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'akun', child: Text('Akun Saya')),
              PopupMenuItem(value: 'konfigurasi', child: Text('Konfigurasi')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Text('Keluar')),
            ],
            child: Row(
              children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary,
                    child: Text(
                        Sesi.instance.userId.isNotEmpty
                            ? Sesi.instance.userId[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13))),
                const SizedBox(width: 8),
                Text(Sesi.instance.userId,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context))),
                Icon(Icons.keyboard_arrow_down,
                    color: AppColors.textSecondaryOf(context), size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipStatus(
      {required IconData icon, required String label, required Color warna}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.latarLembut(warna),
          borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: warna),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: warna)),
        ],
      ),
    );
  }
}
