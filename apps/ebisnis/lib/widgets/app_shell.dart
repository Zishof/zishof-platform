import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import '../api_client.dart';
import '../app_variant.dart';
import '../sesi.dart';
import '../services/pesanan_poller.dart';
import '../services/layar_pelanggan_launcher.dart';
import '../services/toko_aktif_lokal.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_drawer.dart';
import 'app_components.dart';
import 'app_version_label.dart';
import '../screens/akun_saya_screen.dart';
import '../screens/bantuan_screen.dart';
import '../screens/tanya_jawab_screen.dart';
import '../screens/kasir_screen.dart';
import '../screens/ringkasan_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/anggota_screen.dart';
import '../screens/produk_screen.dart';
import '../screens/stok_opname_screen.dart';
import '../screens/kedaluwarsa_screen.dart';
import '../screens/mutasi_antar_outlet_screen.dart';
import '../screens/kulakan_screen.dart';
import '../screens/pengadaan_bast_screen.dart';
import '../screens/pengadaan_po_screen.dart';
import '../screens/pengadaan_pr_screen.dart';
import '../screens/diskon_screen.dart';
import '../screens/cara_bayar_screen.dart';
import '../screens/supplier_screen.dart';
import '../screens/jenis_produk_screen.dart';
import '../screens/grup_produk_screen.dart';
import '../screens/toko_kelola_screen.dart';
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
import '../screens/apotik/beranda_apotik_screen.dart';
import '../screens/apotik/kasir_apotik_screen.dart';
import '../screens/apotik/persediaan_apotik_screen.dart';
import '../screens/apotik/laporan_apotik_screen.dart';
import '../screens/mitrainap/beranda_mitrainap_screen.dart';
import '../screens/mitrainap/properti_hotel_screen.dart';
import '../screens/mitrainap/kamar_hotel_screen.dart';
import '../screens/mitrainap/reservasi_hotel_screen.dart';
import '../screens/mitrainap/resepsionis_hotel_screen.dart';
import '../screens/mitrainap/tiket_dapur_screen.dart';
import '../screens/mitrainap/kontrak_pemilik_screen.dart';
import '../screens/mitrainap/laporan_pemilik_screen.dart';
import '../product_profile.dart';
import 'safe_state.dart';

/// Ambang lebar layar dianggap "desktop" (sidebar+topbar persisten spt
/// referensi) vs "mobile" (drawer+app bar ringkas, pola Material yang sudah
/// dipakai sejak awal proyek) -- 900dp dipilih krn cukup luas utk sidebar
/// 240dp + konten tanpa terasa sempit, tapi masih di bawah lebar tablet
/// landscape kecil.
const kAmbangLebarDesktop = 900.0;

final _menuAktifNotifier =
    ValueNotifier<MenuEBisnis>(AppProductProfile.aktif.isInventorySales
        ? MenuEBisnis.berandaInventorySales
        : AppProductProfile.aktif.isApotik
            ? MenuEBisnis.berandaApotik
            : AppProductProfile.aktif.isMitraInap
                ? MenuEBisnis.berandaMitraInap
                : MenuEBisnis.kasir);

/// Status sidebar desktop disimpan di level aplikasi supaya pilihan pengguna
/// tetap berlaku ketika berpindah halaman. Pada layar kecil AppDrawer tetap
/// dipakai seperti sebelumnya.
final _sidebarRingkasNotifier = ValueNotifier<bool>(false);

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
  grupProduk,
  stokOpname,
  kedaluwarsa,
  mutasiAntarOutlet,
  kulakan,
  pengadaanPr,
  pengadaanPo,
  pengadaanBast,
  penyedia,
  diskon,
  caraBayar,
  returPenjualan,
  riwayatPenjualan,
  laporanTransaksi,
  laporanLaporan,
  laporanKeuangan,
  // Submenu grup "Akuntansi" (2026-08-20). laporanKeuangan dipertahankan sebagai
  // layar "Laporan-Laporan" di dalam grup itu supaya tautan lama tetap sah.
  jurnalUmum,
  postingHpp,
  postingPenjualan,
  kodeAkun,
  grupAkun,
  jenisTransaksi,
  bankAkun,
  riwayatSinkron,
  logError,
  konfigurasi,
  layarPelanggan,
  hakAkses,
  tokoKelola,
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
  labaRugi,
  berandaApotik,
  kasirApotik,
  persediaanApotik,
  laporanApotik,
  berandaMitraInap,
  propertiHotel,
  kamarHotel,
  reservasiHotel,
  resepsionisHotel,
  tiketDapur,
  kontrakPemilik,
  laporanPemilikHotel
}

const _menuKhususApotik = <MenuEBisnis>{
  MenuEBisnis.berandaApotik,
  MenuEBisnis.kasirApotik,
  MenuEBisnis.persediaanApotik,
  MenuEBisnis.laporanApotik,
};

/// Menu khusus varian MitraInap -- kunci server hotel_* (EbisnisMenuKatalog
/// MODUL_MITRAINAP, semuanya KUNCI_DEFAULT_NONAKTIF alias fail-closed).
const _menuKhususMitraInap = <MenuEBisnis>{
  MenuEBisnis.berandaMitraInap,
  MenuEBisnis.propertiHotel,
  MenuEBisnis.kamarHotel,
  MenuEBisnis.reservasiHotel,
  MenuEBisnis.resepsionisHotel,
  MenuEBisnis.tiketDapur,
  MenuEBisnis.kontrakPemilik,
  MenuEBisnis.laporanPemilikHotel,
};

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
  // Fail-closed di server (KUNCI_DEFAULT_NONAKTIF): perubahan harga massal lintas outlet.
  MenuEBisnis.grupProduk: 'grup_produk',
  MenuEBisnis.stokOpname: 'stokopname',
  // Hak kelola mengikuti Stok Opname agar role lama langsung mendapat akses
  // tanpa menunggu migrasi matriks RBAC di server.
  MenuEBisnis.kedaluwarsa: 'stokopname',
  MenuEBisnis.mutasiAntarOutlet: 'mutasistokantaroutlet',
  MenuEBisnis.kulakan: 'kulakan',
  MenuEBisnis.pengadaanPr: 'pengadaan_pr',
  MenuEBisnis.pengadaanPo: 'pengadaan_po',
  MenuEBisnis.pengadaanBast: 'pengadaan_bast',
  // Kunci server "penyedia" (aksesMenu, lihat PosApi.java:1012-1013) sudah
  // ada dari sebelumnya (dialiaskan ke "vendor" juga) -- baru dipakai di
  // sini pertama kali sejak layar CRUD Supplier ditambahkan.
  MenuEBisnis.penyedia: 'penyedia',
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

/// Menu "Sales" murni -- selain gerbang CRUD generik [_kunciMenuIs], HANYA
/// boleh tampil utk aktor berperan Pemilik Sales/Inventory atau Sales
/// Keliling (permintaan user: role lain di Inventory & Sales -- mis. staf
/// gudang/kasir -- tak perlu lihat menu ini). Menu Inventory & Sales LAIN
/// (Master Supplier/Customer, Persediaan, Harga, Hutang/Piutang, Kas &
/// Jurnal, Laba Rugi) TIDAK ikut dibatasi, hanya yg benar² "Sales".
const _menuSalesSaja = <MenuEBisnis>{
  MenuEBisnis.masterSales,
  MenuEBisnis.penjualanSales,
  MenuEBisnis.suratPerintahSales,
  MenuEBisnis.notaSales,
};

bool bolehTampilMenu(MenuEBisnis kunci) {
  if (kunci == MenuEBisnis.hakAkses) return Sesi.instance.isAdmin;
  // Kelola Toko: admin-only, padanan gate isAdmin JSP / TokoApiHelper server.
  if (kunci == MenuEBisnis.tokoKelola) return Sesi.instance.isAdmin;
  // Menu khusus varian "eBisnis Inventory & Sales" -- gerbang level VARIAN
  // (bukan role): tidak pernah dirakit ke sidebar varian POS lama.
  if (kunci == MenuEBisnis.berandaInventorySales) {
    return AppProductProfile.aktif.isInventorySales;
  }
  if (_menuKhususApotik.contains(kunci)) {
    if (!AppProductProfile.aktif.isApotik) return false;
    // Admin tetap dapat membuka beranda untuk provisioning/diagnostik. Layar
    // operasional selain beranda mengikuti hak menu farmasi secara fail-closed.
    if (kunci == MenuEBisnis.berandaApotik || Sesi.instance.isAdmin) {
      return true;
    }
    if (kunci == MenuEBisnis.kasirApotik) {
      return Sesi.instance.bolehMenuVarianBaru('apotik_kasir') ||
          Sesi.instance.bolehMenuVarianBaru('apotik_resep');
    }
    if (kunci == MenuEBisnis.persediaanApotik) {
      return const [
        'apotik_formularium',
        'apotik_batch',
        'apotik_pengadaan',
        'apotik_stok_opname',
        'apotik_retur'
      ].any(Sesi.instance.bolehMenuVarianBaru);
    }
    return Sesi.instance.bolehMenuVarianBaru('apotik_laporan') ||
        Sesi.instance.bolehMenuVarianBaru('apotik_narkotika');
  }
  if (_menuKhususMitraInap.contains(kunci)) {
    if (!AppProductProfile.aktif.isMitraInap) return false;
    // Beranda selalu boleh (menampilkan status kunci); admin global boleh
    // semua utk provisioning. Sisanya fail-closed per kunci hotel_*.
    if (kunci == MenuEBisnis.berandaMitraInap || Sesi.instance.isAdmin) {
      return true;
    }
    if (kunci == MenuEBisnis.propertiHotel) {
      return Sesi.instance.bolehMenuVarianBaru('hotel_properti');
    }
    if (kunci == MenuEBisnis.kamarHotel) {
      return Sesi.instance.bolehMenuVarianBaru('hotel_kamar');
    }
    if (kunci == MenuEBisnis.reservasiHotel) {
      return Sesi.instance.bolehMenuVarianBaru('hotel_reservasi');
    }
    if (kunci == MenuEBisnis.tiketDapur) {
      return Sesi.instance.bolehMenuVarianBaru('hotel_tiket_dapur');
    }
    if (kunci == MenuEBisnis.kontrakPemilik) {
      return Sesi.instance.bolehMenuVarianBaru('hotel_kontrak_pemilik');
    }
    if (kunci == MenuEBisnis.laporanPemilikHotel) {
      return Sesi.instance.bolehMenuVarianBaru('hotel_laporan_pemilik');
    }
    return Sesi.instance.bolehMenuVarianBaru('hotel_checkin') ||
        Sesi.instance.bolehMenuVarianBaru('hotel_folio');
  }
  final kunciIs = _kunciMenuIs[kunci];
  if (kunciIs != null) {
    if (!AppProductProfile.aktif.isInventorySales ||
        !Sesi.instance.bolehMenuIs(kunciIs)) {
      return false;
    }
    if (_menuSalesSaja.contains(kunci)) {
      return Sesi.instance.isPemilikSalesInventory ||
          Sesi.instance.isSalesKeliling;
    }
    return true;
  }
  final kunciServer = _kunciAksesMenu[kunci];
  return kunciServer == null || Sesi.instance.bolehMenu(kunciServer);
}

const _daftarMenu = <_ItemMenuShell>[
  _ItemMenuShell(
      MenuEBisnis.berandaApotik, Icons.dashboard_outlined, 'Dashboard Apotik',
      builder: _bangunBerandaApotik),
  _ItemMenuShell(MenuEBisnis.kasirApotik, Icons.point_of_sale, 'Kasir & Resep',
      builder: _bangunKasirApotik),
  _ItemMenuShell(MenuEBisnis.persediaanApotik, Icons.medication_outlined,
      'Obat & Persediaan',
      builder: _bangunPersediaanApotik),
  _ItemMenuShell(
      MenuEBisnis.laporanApotik, Icons.analytics_outlined, 'Laporan Apotik',
      builder: _bangunLaporanApotik),
  _ItemMenuShell(MenuEBisnis.berandaMitraInap, Icons.night_shelter_outlined,
      'Dashboard MitraInap',
      builder: _bangunBerandaMitraInap),
  _ItemMenuShell(
      MenuEBisnis.propertiHotel, Icons.apartment_outlined, 'Properti Hotel',
      builder: _bangunPropertiHotel),
  _ItemMenuShell(MenuEBisnis.kamarHotel, Icons.meeting_room_outlined,
      'Kamar & Tipe Kamar',
      builder: _bangunKamarHotel),
  _ItemMenuShell(MenuEBisnis.reservasiHotel, Icons.event_available_outlined,
      'Tamu & Reservasi',
      builder: _bangunReservasiHotel),
  _ItemMenuShell(MenuEBisnis.resepsionisHotel, Icons.luggage_outlined,
      'Check-in / Check-out',
      builder: _bangunResepsionisHotel),
  _ItemMenuShell(MenuEBisnis.tiketDapur, Icons.restaurant_outlined,
      'Tiket Dapur',
      builder: _bangunTiketDapur),
  _ItemMenuShell(MenuEBisnis.kontrakPemilik, Icons.handshake_outlined,
      'Kontrak Pemilik',
      builder: _bangunKontrakPemilik),
  _ItemMenuShell(MenuEBisnis.laporanPemilikHotel, Icons.receipt_long_outlined,
      'Laporan Pemilik',
      builder: _bangunLaporanPemilikHotel),
  _ItemMenuShell(MenuEBisnis.berandaInventorySales, Icons.storefront_outlined,
      'Beranda Inventory & Sales',
      builder: _bangunBerandaIS),
  _ItemMenuShell(MenuEBisnis.masterSupplier, Icons.local_shipping_outlined,
      'Master Supplier',
      builder: _bangunMasterSupplier),
  _ItemMenuShell(
      MenuEBisnis.masterCustomer, Icons.people_alt_outlined, 'Master Customer',
      builder: _bangunMasterCustomer),
  _ItemMenuShell(MenuEBisnis.masterSales, Icons.badge_outlined, 'Master Sales',
      builder: _bangunMasterSales),
  _ItemMenuShell(MenuEBisnis.persediaan, Icons.warehouse_outlined,
      'Persediaan & Kartu Stok',
      builder: _bangunPersediaan),
  _ItemMenuShell(
      MenuEBisnis.harga, Icons.price_change_outlined, 'Master & Analisis Harga',
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
  _ItemMenuShell(MenuEBisnis.notaSales, Icons.route_outlined, 'Sesi Nota Sales',
      builder: _bangunNotaSales),
  _ItemMenuShell(
      MenuEBisnis.kasJurnal, Icons.menu_book_outlined, 'Kas & Jurnal',
      builder: _bangunKasJurnal),
  _ItemMenuShell(MenuEBisnis.labaRugi, Icons.stacked_line_chart, 'Laba Rugi',
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
  _ItemMenuShell(
      MenuEBisnis.jenisProduk, Icons.category_outlined, 'Jenis Produk',
      builder: _bangunJenisProduk),
  _ItemMenuShell(
      MenuEBisnis.grupProduk, Icons.workspaces_outline, 'Grup Produk',
      builder: _bangunGrupProduk),
  _ItemMenuShell(
      MenuEBisnis.stokOpname, Icons.fact_check_outlined, 'Stok Opname',
      builder: _bangunStok),
  _ItemMenuShell(
      MenuEBisnis.kedaluwarsa, Icons.event_busy_outlined, 'Kedaluwarsa',
      builder: _bangunKedaluwarsa),
  _ItemMenuShell(MenuEBisnis.mutasiAntarOutlet, Icons.compare_arrows,
      'Mutasi Antar Outlet',
      builder: _bangunMutasiAntarOutlet),
  _ItemMenuShell(MenuEBisnis.kulakan, Icons.local_shipping_outlined, 'Kulakan',
      builder: _bangunKulakan),
  _ItemMenuShell(MenuEBisnis.pengadaanPr, Icons.assignment_outlined,
      'Permintaan Pembelian (PR)',
      builder: _bangunPengadaanPr),
  _ItemMenuShell(MenuEBisnis.pengadaanPo, Icons.receipt_long_outlined,
      'Pemesanan Pembelian (PO)',
      builder: _bangunPengadaanPo),
  _ItemMenuShell(MenuEBisnis.pengadaanBast, Icons.inventory_2_outlined,
      'Penerimaan Barang (BAST)',
      builder: _bangunPengadaanBast),
  _ItemMenuShell(MenuEBisnis.penyedia, Icons.local_shipping_outlined,
      'Supplier (Penyedia)',
      builder: _bangunPenyedia),
  _ItemMenuShell(MenuEBisnis.diskon, Icons.sell_outlined, 'Aturan Diskon',
      builder: _bangunDiskon),
  _ItemMenuShell(
      MenuEBisnis.caraBayar, Icons.payments_outlined, 'Cara Pembayaran',
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
  _ItemMenuShell(
      MenuEBisnis.tokoKelola, Icons.storefront_outlined, 'Kelola Toko',
      builder: _bangunTokoKelola),
];

const _grupMenu = <_GrupMenuShell>[
  _GrupMenuShell('Apotik & Farmasi', [
    MenuEBisnis.berandaApotik,
    MenuEBisnis.kasirApotik,
    MenuEBisnis.persediaanApotik,
    MenuEBisnis.laporanApotik,
  ]),
  _GrupMenuShell('MitraInap', [
    MenuEBisnis.berandaMitraInap,
    MenuEBisnis.propertiHotel,
    MenuEBisnis.kamarHotel,
    MenuEBisnis.reservasiHotel,
    MenuEBisnis.resepsionisHotel,
    MenuEBisnis.tiketDapur,
    MenuEBisnis.kontrakPemilik,
    MenuEBisnis.laporanPemilikHotel,
  ]),
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
    MenuEBisnis.grupProduk,
    MenuEBisnis.stokOpname,
    MenuEBisnis.kedaluwarsa,
    MenuEBisnis.mutasiAntarOutlet,
    MenuEBisnis.kulakan,
    MenuEBisnis.penyedia,
    MenuEBisnis.diskon,
    MenuEBisnis.caraBayar,
  ]),
  _GrupMenuShell('Pengadaan', [
    MenuEBisnis.pengadaanPr,
    MenuEBisnis.pengadaanPo,
    MenuEBisnis.pengadaanBast,
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
    MenuEBisnis.tokoKelola,
  ]),
];

Widget _bangunKasir(BuildContext c) => const KasirScreen();
Widget _bangunRingkasan(BuildContext c) => const RingkasanScreen();
Widget _bangunPesanan(BuildContext c) => const PesananScreen();
Widget _bangunAnggota(BuildContext c) => const AnggotaScreen();
Widget _bangunProduk(BuildContext c) => const ProdukScreen();
Widget _bangunJenisProduk(BuildContext c) => const JenisProdukScreen();
Widget _bangunGrupProduk(BuildContext c) => const GrupProdukScreen();
Widget _bangunStok(BuildContext c) => const StokOpnameScreen();
Widget _bangunKedaluwarsa(BuildContext c) => const KedaluwarsaScreen();
Widget _bangunMutasiAntarOutlet(BuildContext c) =>
    const MutasiAntarOutletScreen();
Widget _bangunKulakan(BuildContext c) => const KulakanScreen();
Widget _bangunPengadaanPr(BuildContext c) => const PengadaanPrScreen();
Widget _bangunPengadaanPo(BuildContext c) => const PengadaanPoScreen();
Widget _bangunPengadaanBast(BuildContext c) => const PengadaanBastScreen();
Widget _bangunDiskon(BuildContext c) => const DiskonScreen();
Widget _bangunCaraBayar(BuildContext c) => const CaraBayarScreen();
Widget _bangunPenyedia(BuildContext c) => const SupplierScreen();
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
Widget _bangunTokoKelola(BuildContext c) => const TokoKelolaScreen();
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
Widget _bangunBerandaApotik(BuildContext c) => const BerandaApotikScreen();
Widget _bangunKasirApotik(BuildContext c) => const KasirApotikScreen();
Widget _bangunPersediaanApotik(BuildContext c) =>
    const PersediaanApotikScreen();
Widget _bangunLaporanApotik(BuildContext c) => const LaporanApotikScreen();
Widget _bangunBerandaMitraInap(BuildContext c) =>
    const BerandaMitraInapScreen();
Widget _bangunPropertiHotel(BuildContext c) => const PropertiHotelScreen();
Widget _bangunKamarHotel(BuildContext c) => const KamarHotelScreen();
Widget _bangunReservasiHotel(BuildContext c) => const ReservasiHotelScreen();
Widget _bangunResepsionisHotel(BuildContext c) =>
    const ResepsionisHotelScreen();
Widget _bangunTiketDapur(BuildContext c) => const TiketDapurScreen();
Widget _bangunKontrakPemilik(BuildContext c) => const KontrakPemilikScreen();
Widget _bangunLaporanPemilikHotel(BuildContext c) =>
    const LaporanPemilikScreen();

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

/// Pemilih toko global untuk semua halaman Desktop/Android. Otorisasi tetap
/// diverifikasi server oleh `pilih_toko_aktif`; daftar di UI bukan sumber hak.
Future<bool> _pilihTokoGlobal(BuildContext context) async {
  final daftar = Sesi.instance.daftarToko;
  if (!Sesi.instance.multiToko || daftar.length < 2) return false;
  final dipilih = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Pindah Toko'),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            children: daftar
                .map((t) => RadioListTile<int>(
                      value: t['id'] as int,
                      groupValue: Sesi.instance.tokoId,
                      title: Text('${t['nama'] ?? 'Tanpa nama'}'),
                      subtitle: t['id'] == Sesi.instance.tokoId
                          ? const Text('Toko aktif saat ini')
                          : null,
                      onChanged: (id) => Navigator.pop(dialogContext, id),
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal')),
      ],
    ),
  );
  if (dipilih == null || dipilih == Sesi.instance.tokoId) return false;
  try {
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': dipilih});
    final konfig = await ApiClient.instance.aksi('konfigurasi');
    Sesi.instance.terapkanKonfig(konfig);
    if (Sesi.instance.userId.isNotEmpty && Sesi.instance.tokoId != null) {
      await TokoAktifLokal.instance
          .simpan(Sesi.instance.userId, Sesi.instance.tokoId!);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Toko aktif diubah ke ${Sesi.instance.tokoNama}.')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Toko belum dapat dipindahkan. Muat ulang hak akses lalu coba lagi. Detail: $e')));
    }
    return false;
  }
}

void _muatUlangHalamanAktif(BuildContext context) {
  final item = _itemMenu(_menuAktifNotifier.value);
  if (item?.builder == null) return;
  Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => item!.builder!(context)));
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
    case MenuEBisnis.grupProduk:
      return 'Grup Produk';
    case MenuEBisnis.stokOpname:
      return 'Stok Opname';
    case MenuEBisnis.kedaluwarsa:
      return 'Kedaluwarsa';
    case MenuEBisnis.mutasiAntarOutlet:
      return 'Mutasi Antar Outlet';
    case MenuEBisnis.kulakan:
      return 'Kulakan';
    case MenuEBisnis.pengadaanPr:
      return 'Permintaan Pembelian (PR)';
    case MenuEBisnis.pengadaanPo:
      return 'Pemesanan Pembelian (PO)';
    case MenuEBisnis.pengadaanBast:
      return 'Penerimaan Barang (BAST)';
    case MenuEBisnis.penyedia:
      return 'Supplier (Penyedia)';
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
      // Layar "Laporan-Laporan" di dalam grup Akuntansi. Labelnya dibedakan dari
      // "Laporan-Laporan" umum supaya penanda menu aktif tidak saling tertukar.
      return 'Laporan-Laporan Keuangan';
    case MenuEBisnis.jurnalUmum:
      return 'Jurnal Umum';
    case MenuEBisnis.postingHpp:
      return 'Posting HPP';
    case MenuEBisnis.postingPenjualan:
      return 'Posting Penjualan';
    case MenuEBisnis.kodeAkun:
      return 'Kode Akun';
    case MenuEBisnis.grupAkun:
      return 'Grup Akun';
    case MenuEBisnis.jenisTransaksi:
      return 'Jenis Transaksi';
    case MenuEBisnis.bankAkun:
      return 'Bank';
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
    case MenuEBisnis.tokoKelola:
      return 'Kelola Toko';
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
    case MenuEBisnis.berandaApotik:
      return 'Dashboard Apotik';
    case MenuEBisnis.kasirApotik:
      return 'Kasir & Resep';
    case MenuEBisnis.persediaanApotik:
      return 'Obat & Persediaan';
    case MenuEBisnis.laporanApotik:
      return 'Laporan Apotik';
    case MenuEBisnis.berandaMitraInap:
      return 'Dashboard MitraInap';
    case MenuEBisnis.propertiHotel:
      return 'Properti Hotel';
    case MenuEBisnis.kamarHotel:
      return 'Kamar & Tipe Kamar';
    case MenuEBisnis.reservasiHotel:
      return 'Tamu & Reservasi';
    case MenuEBisnis.resepsionisHotel:
      return 'Check-in / Check-out';
    case MenuEBisnis.tiketDapur:
      return 'Tiket Dapur';
    case MenuEBisnis.kontrakPemilik:
      return 'Kontrak Pemilik';
    case MenuEBisnis.laporanPemilikHotel:
      return 'Laporan Pemilik';
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
    case 'Kedaluwarsa':
      return MenuEBisnis.kedaluwarsa;
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
    case 'Kelola Toko':
      return MenuEBisnis.tokoKelola;
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
    case 'Dashboard Apotik':
      return MenuEBisnis.berandaApotik;
    case 'Kasir & Resep':
      return MenuEBisnis.kasirApotik;
    case 'Obat & Persediaan':
      return MenuEBisnis.persediaanApotik;
    case 'Laporan Apotik':
      return MenuEBisnis.laporanApotik;
    case 'Dashboard MitraInap':
      return MenuEBisnis.berandaMitraInap;
    case 'Properti Hotel':
      return MenuEBisnis.propertiHotel;
    case 'Kamar & Tipe Kamar':
      return MenuEBisnis.kamarHotel;
    case 'Tamu & Reservasi':
      return MenuEBisnis.reservasiHotel;
    case 'Check-in / Check-out':
      return MenuEBisnis.resepsionisHotel;
    case 'Tiket Dapur':
      return MenuEBisnis.tiketDapur;
    case 'Kontrak Pemilik':
      return MenuEBisnis.kontrakPemilik;
    case 'Laporan Pemilik':
      return MenuEBisnis.laporanPemilikHotel;
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
        final aksiMobile = _bangunAksiMobile(widget.actionsAppBar);
        return Scaffold(
          backgroundColor: AppColors.pageBgOf(context),
          appBar: AppBar(
              title: Text(widget.judul),
              backgroundColor: AppColors.sidebarBg,
              foregroundColor: Colors.white,
              actions: [
                ...aksiMobile,
                if (Sesi.instance.multiToko)
                  IconButton(
                    onPressed: () async {
                      if (await _pilihTokoGlobal(context) && context.mounted) {
                        _muatUlangHalamanAktif(context);
                      }
                    },
                    icon: const Icon(Icons.storefront_outlined),
                    tooltip: 'Pindah toko',
                  ),
                IconButton(
                  key: const Key('tombol-qa-halaman-mobile'),
                  onPressed: () => _bukaTanyaJawab(context),
                  icon: const Icon(Icons.question_answer_outlined),
                  tooltip: 'Tanya jawab halaman ini',
                ),
                IconButton(
                  onPressed: () => _bukaBantuan(context),
                  icon: const Icon(Icons.help_outline),
                  tooltip: 'Bantuan halaman ini',
                ),
                const SizedBox(width: 4),
              ]),
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
            ValueListenableBuilder<bool>(
              valueListenable: _sidebarRingkasNotifier,
              builder: (context, ringkas, _) => _AppSidebar(
                menuAktif: widget.menuAktif,
                ringkas: ringkas,
                onToggle: () => _sidebarRingkasNotifier.value = !ringkas,
              ),
            ),
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
                          Flexible(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              runAlignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (widget.aksiHeader != null)
                                  widget.aksiHeader!,
                                OutlinedButton.icon(
                                  key: const Key('tombol-qa-halaman-desktop'),
                                  onPressed: () => _bukaTanyaJawab(context),
                                  icon: const Icon(
                                      Icons.question_answer_outlined,
                                      size: 18),
                                  label: const Text('Tanya Jawab'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _bukaBantuan(context),
                                  icon:
                                      const Icon(Icons.help_outline, size: 18),
                                  label: const Text('Bantuan'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // Layar spt Kasir sembunyikan judul besar (langsung ke pencarian), TAPI
                    // aksiHeader (mis. toolbar Akun Saya/Layar Pelanggan/Buka Laci/Ganti Toko)
                    // tetap wajib tampil -- gap-closure: sebelumnya baris ini terlewat total
                    // kalau tampilkanJudul false, jadi tombol2 toolbar itu ada di kode tapi tak
                    // pernah ter-render sama sekali di desktop.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (widget.aksiHeader != null) widget.aksiHeader!,
                            OutlinedButton.icon(
                              key: const Key('tombol-qa-halaman-desktop'),
                              onPressed: () => _bukaTanyaJawab(context),
                              icon: const Icon(Icons.question_answer_outlined,
                                  size: 18),
                              label: const Text('Tanya Jawab'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _bukaBantuan(context),
                              icon: const Icon(Icons.help_outline, size: 18),
                              label: const Text('Bantuan'),
                            ),
                          ],
                        ),
                      ),
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

  /// Tombol berlabel yang nyaman di desktop mudah memenuhi seluruh AppBar
  /// ponsel lalu bertabrakan dengan judul/tombol drawer. Bila ada lebih dari
  /// dua aksi, pindahkan [HeaderActionButton] ke satu menu overflow; widget
  /// khusus (misalnya PopupMenuButton bertingkat) tetap dipertahankan.
  List<Widget> _bangunAksiMobile(List<Widget>? actions) {
    if (actions == null || actions.isEmpty) return const [];
    if (actions.length <= 2) return actions;

    final tombolBiasa = actions.whereType<HeaderActionButton>().toList();
    if (tombolBiasa.isEmpty) return actions;
    final khusus = actions.where((a) => a is! HeaderActionButton).take(1);
    return [
      ...khusus,
      PopupMenuButton<int>(
        key: const Key('menu-aksi-halaman-mobile'),
        icon: const Icon(Icons.more_vert),
        tooltip: 'Aksi halaman lainnya',
        onSelected: (index) => tombolBiasa[index].onPressed?.call(),
        itemBuilder: (_) => [
          for (var i = 0; i < tombolBiasa.length; i++)
            PopupMenuItem<int>(
              value: i,
              enabled: tombolBiasa[i].onPressed != null,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(tombolBiasa[i].icon),
                title: Text(tombolBiasa[i].label),
              ),
            ),
        ],
      ),
    ];
  }

  void _bukaBantuan(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BantuanScreen(
        menuId: widget.menuAktif.name,
        menuJudul: widget.judul,
      ),
    ));
  }

  void _bukaTanyaJawab(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TanyaJawabScreen(
        menuId: widget.menuAktif.name,
        menuJudul: widget.judul,
      ),
    ));
  }
}

class _AppSidebar extends StatelessWidget {
  final MenuEBisnis menuAktif;
  final bool ringkas;
  final VoidCallback onToggle;
  const _AppSidebar({
    required this.menuAktif,
    required this.ringkas,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ringkas ? 72 : 240,
      color: AppColors.sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  ringkas ? 10 : 20, 16, ringkas ? 10 : 12, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!ringkas) ...[
                    const Icon(Icons.link, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(AppVariant.namaSidebar,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ],
                  IconButton(
                    key: const Key('tombol-sidebar-ringkas'),
                    onPressed: onToggle,
                    color: Colors.white,
                    iconSize: 20,
                    tooltip: ringkas ? 'Buka menu' : 'Tutup menu',
                    icon: Icon(ringkas ? Icons.menu_open : Icons.menu),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                children: [
                  for (final grup in _grupMenu)
                    _SidebarGroup(
                        grup: grup, menuAktif: menuAktif, ringkas: ringkas),
                ],
              ),
            ),
            if (!ringkas)
              const AppVersionLabel(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 14),
                style: TextStyle(
                  color: AppColors.sidebarText,
                  fontSize: 11,
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
  final bool ringkas;
  const _SidebarGroup({
    required this.grup,
    required this.menuAktif,
    required this.ringkas,
  });

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
          if (ringkas)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Divider(color: Color(0x447D96AE), height: 1),
            )
          else
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
                ringkas: ringkas,
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
  final bool ringkas;
  const _SidebarItem({
    required this.item,
    required this.aktif,
    required this.menuAktif,
    required this.ringkas,
  });

  @override
  Widget build(BuildContext context) {
    final warna = aktif ? AppColors.sidebarTextActive : AppColors.sidebarText;
    final icon = Icon(item.icon, size: 19, color: warna);
    return Tooltip(
      message: ringkas ? item.label : '',
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: ringkas ? 8 : 12, vertical: 2),
        child: Material(
          color: aktif ? AppColors.sidebarBgActive : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pindahMenu(context, item, menuSaatIni: menuAktif),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ringkas ? 8 : 12, vertical: 11),
              child: Row(
                mainAxisAlignment: ringkas
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
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
                  if (!ringkas) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          color: warna,
                          fontSize: 13,
                          fontWeight:
                              aktif ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (item.builder == null)
                      const Icon(Icons.lock_clock_outlined,
                          size: 14, color: AppColors.sidebarText),
                  ],
                ],
              ),
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

  Future<void> _pindahToko() async {
    if (await _pilihTokoGlobal(context) && mounted) {
      _muatUlangHalamanAktif(context);
    }
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
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: Sesi.instance.multiToko ? _pindahToko : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(children: [
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
                  if (Sesi.instance.multiToko) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: AppColors.textSecondaryOf(context)),
                  ],
                ]),
              ),
            ),
          ),
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
