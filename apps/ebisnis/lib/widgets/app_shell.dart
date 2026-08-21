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
import '../screens/pengajuan_anda_screen.dart';
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
import '../screens/pengadaan_bayar_screen.dart';
import '../screens/pengadaan_bdp_screen.dart';
import '../screens/pengadaan_pajak_screen.dart';
import '../screens/pengadaan_tagihan_screen.dart';
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
import '../screens/draft_jurnal_screen.dart';
import '../screens/jurnal_umum_screen.dart';
import '../screens/kode_akun_screen.dart';
import '../screens/siklus_akuntansi_screen.dart';
import '../screens/kas_besar_screen.dart';
import '../screens/kas_kecil_screen.dart';
import '../screens/penggantian_kas_kecil_screen.dart';
import '../screens/pj_kas_besar_screen.dart';
import '../screens/pj_uang_muka_screen.dart';
import '../screens/uang_muka_screen.dart';
import '../screens/anggaran_screen.dart';
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
import 'bantuan_fab.dart';
import '../services/transaksi_outbox_service.dart';

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
  pengadaanTagihan,
  pengadaanDpc,
  pengadaanBdp,
  pengadaanPajak,
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
  draftJurnal,
  jurnalUmum,
  postingHpp,
  postingPenjualan,
  kodeAkun,
  grupAkun,
  jenisTransaksi,
  bankAkun,
  // Enam layar berikut sebelumnya HANYA berupa tab di dalam layar Laporan
  // Keuangan. Sejak 2026-08-21 ikut menjadi submenu grup "Akuntansi" supaya
  // susunan menu Desktop sama persis dengan drawer Android.
  saldoAwalAkun,
  jurnalPenyesuaian,
  tutupBuku,
  postingKulakan,
  postingBayarHutang,
  postingTerimaPiutang,
  // Anggaran/RAB bulanan (2026-08-21): rencana per bulan, revisi, realisasi, dan
  // penggunaan anggaran -- padanan empat layar ZK di paket rab.
  anggaran,
  // Grup "Keuangan" (2026-08-21): enam modul alur kas yang selama ini hanya ada di
  // layar ZK akunting, plus dua menu yang dipindah ke sini dari grup Pengadaan.
  uangMuka,
  pjUangMuka,
  kasBesar,
  pjKasBesar,
  kasKecil,
  penggantianKasKecil,
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

  /// SELURUH grup dapat dilipat (permintaan 21-08-2026) supaya sidebar tidak
  /// penuh oleh menu yang jarang dibuka. Dibiarkan sbg properti -- bukan
  /// konstanta di tempat pemakaian -- agar aturan ini dapat dibaca dan diuji
  /// dari satu tempat bila kelak ada grup yang perlu dikecualikan.
  bool get dapatDilipat => true;

  /// Kondisi awal saat pengguna belum pernah menyentuh grup ini. Bawaannya
  /// TERTUTUP; hanya Operasional yang dibuka sejak awal karena itulah menu
  /// yang dipakai kasir sehari-hari.
  final bool terbukaBawaan;

  const _GrupMenuShell(this.label, this.items, {this.terbukaBawaan = false});
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
  MenuEBisnis.pengadaanTagihan: 'pengadaan_tagihan',
  MenuEBisnis.pengadaanDpc: 'pengadaan_dpc',
  MenuEBisnis.pengadaanBdp: 'pengadaan_bdp',
  MenuEBisnis.pengadaanPajak: 'pengadaan_pajak',
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

/// Submenu grup "Akuntansi" -> kunci `aksesMenu` server. Dibaca FAIL-CLOSED
/// (`bolehMenuVarianBaru`: kunci hilang = tidak boleh) supaya sama persis dengan
/// gerbang drawer Android -- satu perubahan hak akses berlaku di dua platform.
///
/// Enam kunci terakhir milik layar yang sebelumnya hanya berupa tab; sejak menjadi
/// submenu keenamnya terdaftar di `EbisnisMenuKatalog` sehingga admin dapat
/// menyalakan/mematikannya per peran lewat grid CRUD `TbmroleAction`.
const _kunciMenuAkuntansi = <MenuEBisnis, String>{
  MenuEBisnis.draftJurnal: 'draft_jurnal',
  MenuEBisnis.jurnalUmum: 'jurnal_umum',
  MenuEBisnis.postingHpp: 'posting_hpp',
  MenuEBisnis.postingPenjualan: 'posting_penjualan',
  MenuEBisnis.kodeAkun: 'kode_akun',
  MenuEBisnis.grupAkun: 'grup_akun',
  MenuEBisnis.jenisTransaksi: 'jenis_transaksi',
  MenuEBisnis.bankAkun: 'bank_akun',
  MenuEBisnis.saldoAwalAkun: 'saldo_awal_akun',
  MenuEBisnis.jurnalPenyesuaian: 'jurnal_penyesuaian',
  MenuEBisnis.tutupBuku: 'tutup_buku',
  MenuEBisnis.postingKulakan: 'posting_kulakan',
  MenuEBisnis.postingBayarHutang: 'posting_bayar_hutang',
  MenuEBisnis.postingTerimaPiutang: 'posting_terima_piutang',
  MenuEBisnis.anggaran: 'anggaran',
};

/// Submenu grup "Keuangan" -> kunci `aksesMenu` server, FAIL-CLOSED seperti grup
/// Akuntansi. Keenamnya terdaftar di `EbisnisMenuKatalog` (termasuk KUNCI_CRUD)
/// sehingga admin dapat memberi hak Tambah/Ubah/Hapus per peran lewat
/// grid CRUD `TbmroleAction`, bukan sekadar menampilkan/menyembunyikan menunya.
const _kunciMenuKeuangan = <MenuEBisnis, String>{
  MenuEBisnis.uangMuka: 'uang_muka',
  MenuEBisnis.pjUangMuka: 'pj_uang_muka',
  MenuEBisnis.kasBesar: 'kas_besar',
  MenuEBisnis.pjKasBesar: 'pj_kas_besar',
  MenuEBisnis.kasKecil: 'kas_kecil',
  MenuEBisnis.penggantianKasKecil: 'penggantian_kas_kecil',
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
  final kunciAkuntansi = _kunciMenuAkuntansi[kunci];
  if (kunciAkuntansi != null) {
    return Sesi.instance.bolehMenuVarianBaru(kunciAkuntansi);
  }
  final kunciKeuangan = _kunciMenuKeuangan[kunci];
  if (kunciKeuangan != null) {
    return Sesi.instance.bolehMenuVarianBaru(kunciKeuangan);
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
  _ItemMenuShell(
      MenuEBisnis.kamarHotel, Icons.meeting_room_outlined, 'Kamar & Tipe Kamar',
      builder: _bangunKamarHotel),
  _ItemMenuShell(MenuEBisnis.reservasiHotel, Icons.event_available_outlined,
      'Tamu & Reservasi',
      builder: _bangunReservasiHotel),
  _ItemMenuShell(MenuEBisnis.resepsionisHotel, Icons.luggage_outlined,
      'Check-in / Check-out',
      builder: _bangunResepsionisHotel),
  _ItemMenuShell(
      MenuEBisnis.tiketDapur, Icons.restaurant_outlined, 'Tiket Dapur',
      builder: _bangunTiketDapur),
  _ItemMenuShell(
      MenuEBisnis.kontrakPemilik, Icons.handshake_outlined, 'Kontrak Pemilik',
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
  _ItemMenuShell(MenuEBisnis.pengadaanTagihan, Icons.request_quote_outlined,
      'Terima Tagihan Vendor',
      builder: _bangunPengadaanTagihan),
  _ItemMenuShell(
      MenuEBisnis.pengadaanDpc, Icons.payments_outlined, 'Pembayaran Vendor',
      builder: _bangunPengadaanBayar),
  _ItemMenuShell(MenuEBisnis.pengadaanBdp, Icons.local_shipping_outlined,
      'Barang Dalam Proses',
      builder: _bangunPengadaanBdp),
  _ItemMenuShell(
      MenuEBisnis.pengadaanPajak, Icons.account_balance, 'Bayar Pajak',
      builder: _bangunPengadaanPajak),
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
  // Grup "Akuntansi": tiap tab layar Laporan Keuangan punya menunya sendiri,
  // memakai ikon yang sama dengan tabnya supaya pengguna lama tidak kehilangan
  // penanda visual yang sudah dikenal.
  _ItemMenuShell(MenuEBisnis.laporanKeuangan, Icons.folder_open_outlined,
      'Katalog Laporan',
      builder: _bangunLaporanKeuangan),
  _ItemMenuShell(
      MenuEBisnis.anggaran, Icons.savings_outlined, 'Anggaran (RAB Bulanan)',
      builder: _bangunAnggaran),
  _ItemMenuShell(MenuEBisnis.kodeAkun, Icons.account_tree_outlined, 'Kode Akun',
      builder: _bangunKodeAkun),
  _ItemMenuShell(MenuEBisnis.grupAkun, Icons.workspaces_outline, 'Grup Akun',
      builder: _bangunGrupAkun),
  _ItemMenuShell(
      MenuEBisnis.jenisTransaksi, Icons.swap_horiz, 'Jenis Transaksi',
      builder: _bangunJenisTransaksi),
  _ItemMenuShell(MenuEBisnis.bankAkun, Icons.account_balance, 'Bank',
      builder: _bangunBankAkun),
  _ItemMenuShell(
      MenuEBisnis.draftJurnal, Icons.fact_check_outlined, 'Draft Jurnal',
      builder: _bangunDraftJurnal),
  _ItemMenuShell(MenuEBisnis.jurnalUmum, Icons.edit_note, 'Jurnal Umum',
      builder: _bangunJurnalUmum),
  _ItemMenuShell(
      MenuEBisnis.postingHpp, Icons.inventory_2_outlined, 'Posting HPP',
      builder: _bangunPostingHpp),
  _ItemMenuShell(MenuEBisnis.postingPenjualan, Icons.point_of_sale_outlined,
      'Posting Penjualan',
      builder: _bangunPostingPenjualan),
  _ItemMenuShell(MenuEBisnis.saldoAwalAkun, Icons.play_circle_outline,
      'Saldo Awal (Neraca Awal)',
      builder: _bangunSaldoAwalAkun),
  _ItemMenuShell(MenuEBisnis.jurnalPenyesuaian, Icons.rule_folder_outlined,
      'Jurnal Penyesuaian Berkala',
      builder: _bangunJurnalPenyesuaian),
  _ItemMenuShell(
      MenuEBisnis.tutupBuku, Icons.lock_outline, 'Tutup Buku (Laba Ditahan)',
      builder: _bangunTutupBuku),
  _ItemMenuShell(MenuEBisnis.postingKulakan, Icons.local_shipping_outlined,
      'Posting Kulakan',
      builder: _bangunPostingKulakan),
  _ItemMenuShell(MenuEBisnis.postingBayarHutang, Icons.payments_outlined,
      'Posting Bayar Hutang',
      builder: _bangunPostingBayarHutang),
  _ItemMenuShell(MenuEBisnis.postingTerimaPiutang, Icons.savings_outlined,
      'Posting Terima Piutang',
      builder: _bangunPostingTerimaPiutang),
  // Grup "Keuangan". Layarnya menyusul modul demi modul; item tanpa builder
  // memakai pesan "sedang dikerjakan" bawaan _pindahMenu, bukan halaman kosong.
  _ItemMenuShell(MenuEBisnis.uangMuka, Icons.account_balance_wallet_outlined,
      'Uang Muka (Cash Advance)',
      builder: _bangunUangMuka),
  _ItemMenuShell(MenuEBisnis.pjUangMuka, Icons.fact_check_outlined,
      'Pertanggungjawaban Uang Muka',
      builder: _bangunPjUangMuka),
  _ItemMenuShell(MenuEBisnis.kasBesar, Icons.savings_outlined, 'Kas Besar',
      builder: _bangunKasBesar),
  _ItemMenuShell(MenuEBisnis.pjKasBesar, Icons.assignment_turned_in_outlined,
      'Pertanggungjawaban Kas Besar',
      builder: _bangunPjKasBesar),
  _ItemMenuShell(MenuEBisnis.kasKecil, Icons.receipt_long_outlined, 'Kas Kecil',
      builder: _bangunKasKecil),
  _ItemMenuShell(MenuEBisnis.penggantianKasKecil, Icons.autorenew,
      'Penggantian Kas Kecil (Reimbursement)',
      builder: _bangunPenggantianKasKecil),
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

/// Ringkasan grup sidebar utk pengujian: label, apakah dapat dilipat, apakah
/// terbuka secara bawaan, dan jumlah menunya. Sengaja mengembalikan data polos
/// supaya `_GrupMenuShell` tetap privat, sementara aturan tampilannya tetap
/// dapat dikunci oleh test tanpa merender seluruh cangkang aplikasi.
List<({String label, bool dapatDilipat, bool terbukaBawaan, int jumlahItem})>
    ringkasanGrupSidebar() => _grupMenu
        .map((g) => (
              label: g.label,
              dapatDilipat: g.dapatDilipat,
              terbukaBawaan: g.terbukaBawaan,
              jumlahItem: g.items.length,
            ))
        .toList();

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
  _GrupMenuShell(terbukaBawaan: true, 'Operasional', [
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
  _GrupMenuShell(
    'Pengadaan',
    [
      MenuEBisnis.pengadaanPr,
      MenuEBisnis.pengadaanPo,
      MenuEBisnis.pengadaanBast,
      MenuEBisnis.pengadaanTagihan,
      MenuEBisnis.pengadaanBdp,
    ],
  ),
  // Pembayaran Vendor & Bayar Pajak pindah ke sini dari grup Pengadaan
  // (permintaan pemilik produk): keduanya pekerjaan kasir keuangan, bukan
  // pengadaan. KUNCI MENUNYA TIDAK BERUBAH (pengadaan_dpc, pengadaan_pajak)
  // supaya hak akses peran yang sudah diatur tidak ikut ter-reset.
  _GrupMenuShell(
    'Keuangan',
    [
      MenuEBisnis.uangMuka,
      MenuEBisnis.pjUangMuka,
      MenuEBisnis.kasBesar,
      MenuEBisnis.pjKasBesar,
      MenuEBisnis.kasKecil,
      MenuEBisnis.penggantianKasKecil,
      MenuEBisnis.pengadaanPajak,
      MenuEBisnis.pengadaanDpc,
    ],
  ),
  _GrupMenuShell('Transaksi & Laporan', [
    MenuEBisnis.returPenjualan,
    MenuEBisnis.riwayatPenjualan,
    MenuEBisnis.laporanTransaksi,
    MenuEBisnis.laporanLaporan,
  ]),
  // Urutannya mengikuti urutan tab pada layar Laporan Keuangan supaya pengguna
  // lama menemukan menu di tempat yang sama. Dapat dilipat spt grup Pengadaan:
  // isinya panjang dan tidak dibuka tiap hari.
  _GrupMenuShell(
    'Akuntansi',
    [
      MenuEBisnis.laporanKeuangan,
      MenuEBisnis.draftJurnal,
      MenuEBisnis.anggaran,
      MenuEBisnis.kodeAkun,
      MenuEBisnis.grupAkun,
      MenuEBisnis.jenisTransaksi,
      MenuEBisnis.bankAkun,
      MenuEBisnis.jurnalUmum,
      MenuEBisnis.postingHpp,
      MenuEBisnis.postingPenjualan,
      MenuEBisnis.saldoAwalAkun,
      MenuEBisnis.jurnalPenyesuaian,
      MenuEBisnis.tutupBuku,
      MenuEBisnis.postingKulakan,
      MenuEBisnis.postingBayarHutang,
      MenuEBisnis.postingTerimaPiutang,
    ],
  ),
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
Widget _bangunPengadaanTagihan(BuildContext c) =>
    const PengadaanTagihanScreen();
Widget _bangunPengadaanBayar(BuildContext c) => const PengadaanBayarScreen();
Widget _bangunPengadaanBdp(BuildContext c) => const PengadaanBdpScreen();
Widget _bangunPengadaanPajak(BuildContext c) => const PengadaanPajakScreen();
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

/// Layar akuntansi memakai LAYAR YANG SAMA dengan tab-nya, hanya mendarat di
/// bagian yang tepat -- tidak ada duplikasi logika posting/jurnal.
Widget _bangunAnggaran(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.anggaran,
    'Anggaran (RAB Bulanan)',
    'Rencana belanja per bulan, revisi, realisasi, dan penggunaan anggaran',
    const AnggaranScreen());
Widget _bangunKodeAkun(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.kodeAkun,
    'Kode Akun',
    'Bagan akun (chart of account) beserta kode dan saldo normalnya',
    const KodeAkunScreen(tabAwal: 0));
Widget _bangunGrupAkun(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.grupAkun,
    'Grup Akun',
    'Pengelompokan akun untuk klasifikasi laporan',
    const KodeAkunScreen(tabAwal: 4));
Widget _bangunJenisTransaksi(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.jenisTransaksi,
    'Jenis Transaksi',
    'Jenis transaksi beserta akun debet/kredit bawaannya',
    const KodeAkunScreen(tabAwal: 3));
Widget _bangunBankAkun(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.bankAkun,
    'Bank',
    'Daftar bank beserta kode dan akun kas/bank yang dipakai jurnal',
    const KodeAkunScreen(tabAwal: 2));
Widget _bangunDraftJurnal(BuildContext c) => const DraftJurnalScreen();
Widget _bangunJurnalUmum(BuildContext c) => const JurnalUmumScreen();
Widget _bangunSaldoAwalAkun(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.saldoAwalAkun,
    'Saldo Awal (Neraca Awal)',
    'Saldo pembukaan tiap akun sebelum sistem dipakai',
    const SiklusAkuntansiScreen(tabAwal: 0));
Widget _bangunJurnalPenyesuaian(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.jurnalPenyesuaian,
    'Jurnal Penyesuaian Berkala',
    'Amortisasi, akrual, dan penyisihan yang dijurnal tiap periode',
    const SiklusAkuntansiScreen(tabAwal: 1));
Widget _bangunTutupBuku(BuildContext c) => _halamanAkuntansi(
    MenuEBisnis.tutupBuku,
    'Tutup Buku (Laba Ditahan)',
    'Menutup akun laba rugi ke Laba Ditahan pada akhir periode',
    const SiklusAkuntansiScreen(tabAwal: 2));

/// Bungkus layar akuntansi yang badannya berupa tab (KodeAkun/Siklus) menjadi
/// halaman utuh: keduanya mengurus scroll sendiri, jadi [AppShell.scrollable]
/// wajib false.
Widget _halamanAkuntansi(
        MenuEBisnis menu, String judul, String subjudul, Widget badan) =>
    AppShell(
        menuAktif: menu,
        judul: judul,
        subjudul: subjudul,
        scrollable: false,
        body: badan);

/// Lima posting tetap memakai LaporanScreen supaya panel drafnya persis sama
/// dengan tab lamanya; [LaporanScreen.bukaPosting] yang menentukan tab mana yang
/// terbuka begitu layar tampil.
Widget _postingKeuangan(
        MenuEBisnis menu, String judul, String subjudul, String idPendukung) =>
    LaporanScreen(
      aksiKatalog: 'laporan_keuangan_katalog',
      menuAktif: menu,
      judul: judul,
      subjudul: subjudul,
      bukaPosting: idPendukung,
    );
Widget _bangunPostingHpp(BuildContext c) => _postingKeuangan(
    MenuEBisnis.postingHpp,
    'Posting HPP',
    'Membukukan harga pokok penjualan ke buku besar',
    'posting_hpp');
Widget _bangunPostingPenjualan(BuildContext c) => _postingKeuangan(
    MenuEBisnis.postingPenjualan,
    'Posting Penjualan',
    'Membukukan penjualan kasir ke buku besar',
    'posting_penjualan');
Widget _bangunPostingKulakan(BuildContext c) => _postingKeuangan(
    MenuEBisnis.postingKulakan,
    'Posting Kulakan',
    'Membukukan pembelian barang toko (persediaan & utang supplier)',
    'posting_kulakan');
Widget _bangunPostingBayarHutang(BuildContext c) => _postingKeuangan(
    MenuEBisnis.postingBayarHutang,
    'Posting Bayar Hutang',
    'Membukukan pembayaran hutang ke supplier toko',
    'posting_bayar_hutang');
Widget _bangunPostingTerimaPiutang(BuildContext c) => _postingKeuangan(
    MenuEBisnis.postingTerimaPiutang,
    'Posting Terima Piutang',
    'Membukukan penerimaan piutang dari pelanggan toko',
    'posting_terima_piutang');
Widget _bangunUangMuka(BuildContext c) => const UangMukaScreen();
Widget _bangunPjUangMuka(BuildContext c) => const PjUangMukaScreen();
Widget _bangunKasBesar(BuildContext c) => const KasBesarScreen();
Widget _bangunPjKasBesar(BuildContext c) => const PjKasBesarScreen();
Widget _bangunKasKecil(BuildContext c) => const KasKecilScreen();
Widget _bangunPenggantianKasKecil(BuildContext c) =>
    const PenggantianKasKecilScreen();
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

/// true bila menu ini punya saudara segrup yang boleh ditampilkan, sehingga
/// pemilih halaman layak dipasang.
bool _punyaDropdownGrup(MenuEBisnis kunci) {
  final grup = _grupDariMenu(kunci);
  if (grup == null) return false;
  return grup.items.where(bolehTampilMenu).length >= 2;
}

/// Grup sidebar yang memuat [kunci]; null bila menu itu berdiri sendiri.
_GrupMenuShell? _grupDariMenu(MenuEBisnis kunci) {
  for (final grup in _grupMenu) {
    if (grup.items.contains(kunci)) return grup;
  }
  return null;
}

/// Pemilih halaman satu grup, diletakkan tepat di bawah judul -- bersebelahan
/// dengan panel menu.
///
/// Menggantikan deretan tab yang dulu berjajar di atas layar Akuntansi. Tab itu
/// menyalin isi sidebar, sehingga satu halaman menampilkan dua daftar menu yang
/// sama; begitu isinya belasan, deretnya melebar sampai memotong judul halaman.
/// Dropdown menyampaikan hal yang sama dalam satu baris dan tetap menunjukkan
/// halaman mana yang sedang dibuka.
class _DropdownGrupMenu extends StatelessWidget {
  final MenuEBisnis menuAktif;

  const _DropdownGrupMenu({required this.menuAktif});

  @override
  Widget build(BuildContext context) {
    final grup = _grupDariMenu(menuAktif);
    if (grup == null) return const SizedBox.shrink();
    final daftar = grup.items
        .where(bolehTampilMenu)
        .map(_itemMenu)
        .whereType<_ItemMenuShell>()
        .toList();
    // Satu halaman saja tidak butuh pemilih.
    if (daftar.length < 2) return const SizedBox.shrink();
    final aktif = _itemMenu(menuAktif);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: PopupMenuButton<MenuEBisnis>(
        tooltip: 'Pindah halaman ${grup.label}',
        position: PopupMenuPosition.under,
        onSelected: (kunci) {
          final item = _itemMenu(kunci);
          if (item != null) _pindahMenu(context, item, menuSaatIni: menuAktif);
        },
        itemBuilder: (context) => daftar
            .map((item) => PopupMenuItem<MenuEBisnis>(
                  value: item.kunci,
                  child: Row(children: [
                    Icon(item.icon,
                        size: 18,
                        color: item.kunci == menuAktif
                            ? AppColors.primary
                            : AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 10),
                    Text(item.label,
                        style: TextStyle(
                            fontWeight: item.kunci == menuAktif
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: item.kunci == menuAktif
                                ? AppColors.primary
                                : AppColors.textPrimaryOf(context))),
                  ]),
                ))
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.latarLembut(AppColors.primary),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(aktif?.icon ?? Icons.account_balance_outlined,
                size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(aktif?.label ?? grup.label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 20, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
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

/// Muat daftar toko untuk combo filter (aksi `toko_filter_list`).
///
/// Server yang memutuskan apakah pengguna ini boleh melihat seluruh toko dan
/// toko mana saja yang masuk daftar -- klien tidak menyimpulkannya sendiri.
/// Aman dipanggil berulang; kegagalan dibiarkan senyap karena filter ini
/// pelengkap, bukan syarat aplikasi berjalan.
Future<void> muatDaftarTokoFilter() async {
  try {
    final res = await ApiClient.instance.aksi('toko_filter_list');
    final data = res['data'];
    Sesi.instance.bolehSemuaToko = res['bolehSemuaToko'] == true;
    if (data is List) {
      Sesi.instance.daftarTokoFilter = data
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry('$k', v)))
          .toList();
    }
  } catch (_) {
    // Biarkan: chip tetap menampilkan nama toko aktif spt sebelumnya.
  }
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
    case MenuEBisnis.pengadaanTagihan:
      return 'Terima Tagihan Vendor';
    case MenuEBisnis.pengadaanDpc:
      return 'Pembayaran Vendor';
    case MenuEBisnis.pengadaanBdp:
      return 'Barang Dalam Proses';
    case MenuEBisnis.pengadaanPajak:
      return 'Bayar Pajak';
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
    case MenuEBisnis.draftJurnal:
      return 'Draft Jurnal';
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
    case MenuEBisnis.saldoAwalAkun:
      return 'Saldo Awal (Neraca Awal)';
    case MenuEBisnis.jurnalPenyesuaian:
      return 'Jurnal Penyesuaian Berkala';
    case MenuEBisnis.tutupBuku:
      return 'Tutup Buku (Laba Ditahan)';
    case MenuEBisnis.postingKulakan:
      return 'Posting Kulakan';
    case MenuEBisnis.postingBayarHutang:
      return 'Posting Bayar Hutang';
    case MenuEBisnis.postingTerimaPiutang:
      return 'Posting Terima Piutang';
    case MenuEBisnis.uangMuka:
      return 'Uang Muka (Cash Advance)';
    case MenuEBisnis.pjUangMuka:
      return 'Pertanggungjawaban Uang Muka';
    case MenuEBisnis.kasBesar:
      return 'Kas Besar';
    case MenuEBisnis.pjKasBesar:
      return 'Pertanggungjawaban Kas Besar';
    case MenuEBisnis.kasKecil:
      return 'Kas Kecil';
    case MenuEBisnis.penggantianKasKecil:
      return 'Penggantian Kas Kecil (Reimbursement)';
    case MenuEBisnis.anggaran:
      return 'Anggaran (RAB Bulanan)';
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
    case 'Laporan-Laporan Keuangan':
    case 'Katalog Laporan':
      return MenuEBisnis.laporanKeuangan;
    case 'Kode Akun':
      return MenuEBisnis.kodeAkun;
    case 'Grup Akun':
      return MenuEBisnis.grupAkun;
    case 'Jenis Transaksi':
      return MenuEBisnis.jenisTransaksi;
    case 'Bank':
      return MenuEBisnis.bankAkun;
    case 'Jurnal Umum':
      return MenuEBisnis.jurnalUmum;
    case 'Draft Jurnal':
      return MenuEBisnis.draftJurnal;
    case 'Posting HPP':
      return MenuEBisnis.postingHpp;
    case 'Posting Penjualan':
      return MenuEBisnis.postingPenjualan;
    case 'Saldo Awal (Neraca Awal)':
      return MenuEBisnis.saldoAwalAkun;
    case 'Jurnal Penyesuaian Berkala':
      return MenuEBisnis.jurnalPenyesuaian;
    case 'Tutup Buku (Laba Ditahan)':
      return MenuEBisnis.tutupBuku;
    case 'Posting Kulakan':
      return MenuEBisnis.postingKulakan;
    case 'Posting Bayar Hutang':
      return MenuEBisnis.postingBayarHutang;
    case 'Posting Terima Piutang':
      return MenuEBisnis.postingTerimaPiutang;
    case 'Uang Muka (Cash Advance)':
      return MenuEBisnis.uangMuka;
    case 'Pertanggungjawaban Uang Muka':
      return MenuEBisnis.pjUangMuka;
    case 'Kas Besar':
      return MenuEBisnis.kasBesar;
    case 'Pertanggungjawaban Kas Besar':
      return MenuEBisnis.pjKasBesar;
    case 'Kas Kecil':
      return MenuEBisnis.kasKecil;
    case 'Penggantian Kas Kecil (Reimbursement)':
      return MenuEBisnis.penggantianKasKecil;
    case 'Anggaran (RAB Bulanan)':
      return MenuEBisnis.anggaran;
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

  /// Gabungkan FAB milik layar dengan tombol bantuan mengambang.
  ///
  /// Tombol bantuan dipasang terpusat di sini supaya SELURUH layar yang memakai
  /// [AppShell] memperolehnya sekaligus, tanpa perlu menyunting satu per satu.
  /// Bila layar sudah punya FAB sendiri, keduanya ditumpuk: FAB layar di atas,
  /// tombol bantuan di bawah, sehingga tombol utama layar tetap yang terdekat
  /// dengan ibu jari.
  Widget _fabDenganBantuan() {
    final bantuan =
        BantuanFab(menuId: widget.menuAktif.name, judul: widget.judul);
    final milikLayar = widget.floatingActionButton;
    if (milikLayar == null) {
      return bantuan;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [milikLayar, const SizedBox(height: 12), bantuan],
    );
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
                // Padanan Android untuk tombol "Pengajuan Anda" di bilah atas
                // Desktop -- gerbang hak aksesnya sama (Tbmrole.workflow).
                if (Sesi.instance.bolehMenu('pengajuan_anda'))
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PengajuanAndaScreen())),
                    icon: const Icon(Icons.fact_check_outlined),
                    tooltip: 'Pengajuan Anda',
                  ),
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
          floatingActionButton: _fabDenganBantuan(),
          // Di layar sempit judul halaman pindah ke AppBar, jadi pemilih grup
          // dipasang tepat di atas badan halaman -- tetap satu baris, tidak
          // kembali menjadi deretan tab yang memakan lebar.
          body: _punyaDropdownGrup(widget.menuAktif)
              ? Column(children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _DropdownGrupMenu(menuAktif: widget.menuAktif),
                    ),
                  ),
                  Expanded(child: widget.body),
                ])
              : widget.body,
          bottomNavigationBar: widget.bottomBar,
        );
      }
      return Scaffold(
        backgroundColor: AppColors.pageBgOf(context),
        floatingActionButton: _fabDenganBantuan(),
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
                                // Pemilih halaman segrup (mis. Akuntansi):
                                // menggantikan deretan tab di dalam layar.
                                _DropdownGrupMenu(menuAktif: widget.menuAktif),
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

class _SidebarGroup extends StatefulWidget {
  final _GrupMenuShell grup;
  final MenuEBisnis menuAktif;
  final bool ringkas;
  const _SidebarGroup({
    required this.grup,
    required this.menuAktif,
    required this.ringkas,
  });

  @override
  State<_SidebarGroup> createState() => _SidebarGroupState();
}

class _SidebarGroupState extends State<_SidebarGroup> {
  /// Null berarti pengguna belum menyentuh grup ini, sehingga kondisinya
  /// mengikuti bawaan grup ([_GrupMenuShell.terbukaBawaan]) atau terbuka
  /// karena menu aktif berada di dalamnya.
  bool? _dibukaPengguna;

  bool get _berisiMenuAktif => widget.grup.items.contains(widget.menuAktif);

  bool get _terbuka {
    if (!widget.grup.dapatDilipat) return true;
    // Menu aktif SELALU membuka grupnya, bahkan bila bawaannya tertutup --
    // kalau tidak, pengguna kehilangan petunjuk posisinya sendiri.
    return _dibukaPengguna ?? (widget.grup.terbukaBawaan || _berisiMenuAktif);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.grup.items
        .map(_itemMenu)
        .whereType<_ItemMenuShell>()
        .where((item) => bolehTampilMenu(item.kunci))
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    // Mode ringkas hanya menampilkan ikon; melipat di sana justru menyembunyikan
    // satu-satunya jalan menuju menu itu, jadi isinya selalu ditampilkan.
    final bolehLipat = widget.grup.dapatDilipat && !widget.ringkas;
    final tampilkanIsi = !bolehLipat || _terbuka;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.ringkas)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Divider(color: Color(0x447D96AE), height: 1),
            )
          else if (bolehLipat)
            InkWell(
              onTap: () => setState(() => _dibukaPengguna = !_terbuka),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 12, 7),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      widget.grup.label.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.sidebarText,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _terbuka ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.sidebarText,
                  ),
                ]),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 12, 7),
              child: Text(
                widget.grup.label.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.sidebarText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (tampilkanIsi)
            ...items.map((item) => _SidebarItem(
                  item: item,
                  aktif: item.kunci == widget.menuAktif,
                  menuAktif: widget.menuAktif,
                  ringkas: widget.ringkas,
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
  int _gagalSync = 0;
  bool _sinkronBerjalan = false;

  @override
  void initState() {
    super.initState();
    CoreDb.instance.sesiKasVersi.addListener(_muat);
    _muat();
    // Daftar toko utk combo filter ditarik sekali saat bilah atas dipasang.
    // Ditaruh di sini (bukan saat login) supaya sesi lama yang token-nya masih
    // tersimpan pun tetap mendapatkannya tanpa perlu masuk ulang.
    if (Sesi.instance.daftarTokoFilter.isEmpty) {
      muatDaftarTokoFilter().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    CoreDb.instance.sesiKasVersi.removeListener(_muat);
    super.dispose();
  }

  Future<void> _muat() async {
    final kas = await CoreDb.instance.sesiKasAktif();
    // Hitung PENDING dan GAGAL sekaligus. Sebelumnya chip hanya membaca
    // PENDING, sehingga nota yang sudah divonis GAGAL -- yang justru TIDAK
    // akan dijemput retry otomatis -- tampil seolah semuanya beres.
    final tertahan = await TransaksiOutboxService.instance.hitungTertahan();
    if (mounted) {
      setStateIfMounted(() {
        _kasAktif = kas;
        _pendingSync = tertahan.pending;
        _gagalSync = tertahan.gagal;
      });
    }
  }

  /// Sinkronisasi MANUAL: mengembalikan nota GAGAL ke antrean lalu mengirim
  /// semuanya. Dipisahkan dari timer otomatis supaya pengiriman ulang atas
  /// nota yang pernah ditolak selalu merupakan keputusan pengguna.
  Future<void> _sinkronkanManual() async {
    if (_sinkronBerjalan) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      final hasil =
          await TransaksiOutboxService.instance.sinkronkan(sertakanGagal: true);
      await _muat();
      if (!mounted) return;
      final sisa = _pendingSync + _gagalSync;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hasil.total == 0
            ? 'Tidak ada transaksi tertahan.'
            : '${hasil.berhasil} dari ${hasil.total} transaksi terkirim.'
                '${sisa > 0 ? ' Sisa $sisa masih tertahan.' : ''}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sinkronisasi gagal: $e')));
    } finally {
      setStateIfMounted(() => _sinkronBerjalan = false);
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

  /// Combo filter toko untuk peran berizin "Boleh melihat seluruh toko".
  ///
  /// Berbeda dgn [_pindahToko] yang MENGUBAH toko aktif di server (dan ikut
  /// mengubah tempat transaksi dicatat), pilihan di sini hanya menyaring
  /// tampilan Dashboard dan Laporan -- disisipkan ke payload oleh ApiClient.
  Future<void> _pilihFilterToko() async {
    final sesi = Sesi.instance;
    if (sesi.daftarTokoFilter.isEmpty) {
      await muatDaftarTokoFilter();
      if (!mounted) return;
    }
    final dipilih = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Tampilkan data toko'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'semua'),
            child: Row(children: [
              Icon(Icons.select_all,
                  size: 18, color: AppColors.textSecondaryOf(dialogContext)),
              const SizedBox(width: 10),
              const Text('Semua Toko'),
              if (sesi.tokoFilter == null) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16, color: AppColors.success),
              ],
            ]),
          ),
          const Divider(height: 1),
          ...sesi.daftarTokoFilter.map((t) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, t['id']),
                child: Row(children: [
                  Icon(Icons.storefront_outlined,
                      size: 18,
                      color: AppColors.textSecondaryOf(dialogContext)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${t['nama'] ?? ''}')),
                  if (sesi.tokoFilter == t['id'])
                    const Icon(Icons.check, size: 16, color: AppColors.success),
                ]),
              )),
        ],
      ),
    );
    if (dipilih == null || !mounted) return;
    setState(() {
      sesi.tokoFilter = dipilih == 'semua' ? null : dipilih as int;
    });
    _muatUlangHalamanAktif(context);
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
              // Peran berizin lintas toko memakai chip ini sbg FILTER laporan
              // (termasuk pilihan "Semua Toko"); peran multi-toko biasa tetap
              // memakainya utk BERPINDAH toko aktif. Keduanya beda arti, jadi
              // yang berizin didahulukan.
              onTap: Sesi.instance.bolehSemuaToko
                  ? _pilihFilterToko
                  : (Sesi.instance.multiToko ? _pindahToko : null),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(children: [
                  Icon(Icons.storefront_outlined,
                      color: AppColors.textSecondaryOf(context), size: 18),
                  const SizedBox(width: 6),
                  Text(
                      Sesi.instance.bolehSemuaToko
                          ? Sesi.instance.namaTokoFilter
                          : (Sesi.instance.tokoNama.isEmpty
                              ? AppVariant.namaAplikasi
                              : Sesi.instance.tokoNama),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context))),
                  if (Sesi.instance.multiToko ||
                      Sesi.instance.bolehSemuaToko) ...[
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
          // Tombol "Pengajuan Anda" (Workflow / Proses SOP) -- padanan tombol
          // bernama sama di bilah menu versi ZKoss (MainAction2.eWorkflowButton).
          // Muncul hanya bila server memberi hak aksesnya lewat Tbmrole.workflow;
          // gerbang sebenarnya tetap ditegakkan server di setiap aksi sop_*.
          if (Sesi.instance.bolehMenu('pengajuan_anda')) ...[
            Tooltip(
              message: 'Pengajuan, persetujuan, dan alur kerja Anda',
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PengajuanAndaScreen())),
                borderRadius: BorderRadius.circular(20),
                child: _chipStatus(
                  icon: Icons.fact_check_outlined,
                  label: 'Pengajuan Anda',
                  warna: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Builder(builder: (ctx) {
            final tertahan = _pendingSync + _gagalSync;
            final adaGagal = _gagalSync > 0;
            return Tooltip(
              message: _sinkronBerjalan
                  ? 'Sedang menyinkronkan...'
                  : tertahan == 0
                      ? 'Semua transaksi sudah terkirim. Klik untuk memeriksa lagi.'
                      : 'Klik untuk mengirim ulang sekarang'
                          '${adaGagal ? ' ($_gagalSync perlu ditinjau)' : ''}',
              child: InkWell(
                onTap: _sinkronBerjalan ? null : _sinkronkanManual,
                borderRadius: BorderRadius.circular(20),
                child: _chipStatus(
                  icon: _sinkronBerjalan
                      ? Icons.sync
                      : tertahan == 0
                          ? Icons.cloud_done_outlined
                          : adaGagal
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_sync_outlined,
                  label: _sinkronBerjalan
                      ? 'Menyinkronkan...'
                      : tertahan == 0
                          ? 'Sinkronkan'
                          : '$tertahan Tertahan',
                  warna: tertahan == 0
                      ? AppColors.teal
                      : adaGagal
                          ? AppColors.danger
                          : AppColors.warning,
                ),
              ),
            );
          }),
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
