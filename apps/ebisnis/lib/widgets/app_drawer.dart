import 'package:flutter/material.dart';
import '../app_variant.dart';
import '../sesi.dart';
import '../services/layar_pelanggan_launcher.dart';
import '../services/pesanan_poller.dart';
import '../theme/app_colors.dart';
import '../screens/kasir_screen.dart';
import '../screens/produk_screen.dart';
import '../screens/anggota_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/stok_opname_screen.dart';
import '../screens/kedaluwarsa_screen.dart';
import '../screens/mutasi_antar_outlet_screen.dart';
import '../screens/jenis_produk_screen.dart';
import '../screens/grup_produk_screen.dart';
import '../screens/toko_kelola_screen.dart';
import '../screens/cara_bayar_screen.dart';
import '../screens/laporan_transaksi_screen.dart';
import '../screens/ringkasan_screen.dart';
import '../screens/diskon_screen.dart';
import '../screens/kulakan_screen.dart';
import '../screens/pengadaan_bast_screen.dart';
import '../screens/pengadaan_bayar_screen.dart';
import '../screens/pengadaan_bdp_screen.dart';
import '../screens/pengadaan_pajak_screen.dart';
import '../screens/pengadaan_po_screen.dart';
import '../screens/pengadaan_pr_screen.dart';
import '../screens/pengadaan_tagihan_screen.dart';
import '../screens/supplier_screen.dart';
import '../screens/konfigurasi_screen.dart';
import '../screens/log_error_screen.dart';
import '../screens/retur_penjualan_screen.dart';
import '../screens/riwayat_penjualan_screen.dart';
import '../screens/riwayat_sinkronisasi_screen.dart';
import '../screens/laporan_screen.dart';
import '../screens/draft_jurnal_screen.dart';
import '../screens/jurnal_umum_screen.dart';
import '../screens/kode_akun_screen.dart';
import '../screens/siklus_akuntansi_screen.dart';
import '../screens/kas_besar_screen.dart';
import '../screens/kas_kecil_screen.dart';
import '../screens/dana_talangan_screen.dart';
import '../screens/penggantian_kas_kecil_screen.dart';
import '../screens/pj_kas_besar_screen.dart';
import '../screens/pj_uang_muka_screen.dart';
import '../screens/uang_muka_screen.dart';
import '../screens/anggaran_screen.dart';
import '../screens/hak_akses_screen.dart';
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
import 'app_version_label.dart';

/// Menu navigasi utama -- padanan sidebar kiri versi Electron (Kasir/Ringkasan/
/// Pesanan/Customer-Anggota/Produk/Stok Opname/Kulakan/Aturan Diskon/Laporan
/// Transaksi/Laporan-Laporan/Riwayat Sinkronisasi/Log Error/Konfigurasi).
/// Layar yang belum dibangun ditandai "Segera Hadir" (dinonaktifkan) -- lihat
/// task #182-189 utk urutan pengerjaan, jangan hapus entrinya supaya progres
/// tetap terlihat sambil layar-layar itu menyusul satu per satu.
/// Bungkus halaman untuk layar akuntansi yang badannya berupa Column bertab
/// (KodeAkunScreen & SiklusAkuntansiScreen). Keduanya BUKAN halaman utuh: tanpa
/// Scaffold, TabBar/ListTile di dalamnya gagal dengan "No Material widget found"
/// begitu menu dibuka. Sidebar Desktop membungkusnya dengan AppShell; drawer
/// Android memakai Scaffold ringkas ini supaya keduanya sama-sama aman.
Widget _halamanAkuntansi(String judul, Widget badan) => Scaffold(
      appBar: AppBar(title: Text(judul)),
      body: badan,
    );

/// Tiga submenu siklus akuntansi memakai layar yang sama, beda tab awalnya.
Widget _halamanSiklus(String judul, int tabAwal) =>
    _halamanAkuntansi(judul, SiklusAkuntansiScreen(tabAwal: tabAwal));

class AppDrawer extends StatelessWidget {
  final String menuAktif;
  final ValueChanged<String>? onPilihMenu;
  const AppDrawer({super.key, this.menuAktif = 'Kasir', this.onPilihMenu});

  static final ValueNotifier<String> menuAktifNotifier =
      ValueNotifier<String>('Kasir');

  void _pindahMenu(
    BuildContext context, {
    required String label,
    required WidgetBuilder builder,
  }) {
    if (menuAktif == label) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    menuAktifNotifier.value = label;
    if (onPilihMenu != null) {
      onPilihMenu!(label);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.cardBgOf(context),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 112,
              child: DrawerHeader(
                margin: EdgeInsets.zero,
                decoration: const BoxDecoration(color: Color(0xFF1E3A5F)),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    Sesi.instance.tokoNama.isEmpty
                        ? AppVariant.namaAplikasi
                        : Sesi.instance.tokoNama,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: menuAktifNotifier,
                builder: (context, _, __) => Scrollbar(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (AppProductProfile.aktif.isApotik)
                        _ItemMenu(
                          icon: Icons.dashboard_outlined,
                          label: 'Dashboard Apotik',
                          aktif: menuAktif == 'Dashboard Apotik',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Dashboard Apotik',
                            builder: (_) => const BerandaApotikScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isApotik &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_kasir') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_resep')))
                        _ItemMenu(
                          icon: Icons.point_of_sale,
                          label: 'Kasir & Resep',
                          aktif: menuAktif == 'Kasir & Resep',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kasir & Resep',
                            builder: (_) => const KasirApotikScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isApotik &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_formularium') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_batch') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_pengadaan') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_stok_opname') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_retur')))
                        _ItemMenu(
                          icon: Icons.medication_outlined,
                          label: 'Obat & Persediaan',
                          aktif: menuAktif == 'Obat & Persediaan',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Obat & Persediaan',
                            builder: (_) => const PersediaanApotikScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isApotik &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_laporan') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('apotik_narkotika')))
                        _ItemMenu(
                          icon: Icons.analytics_outlined,
                          label: 'Laporan Apotik',
                          aktif: menuAktif == 'Laporan Apotik',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Laporan Apotik',
                            builder: (_) => const LaporanApotikScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap)
                        _ItemMenu(
                          icon: Icons.night_shelter_outlined,
                          label: 'Dashboard MitraInap',
                          aktif: menuAktif == 'Dashboard MitraInap',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Dashboard MitraInap',
                            builder: (_) => const BerandaMitraInapScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('hotel_properti')))
                        _ItemMenu(
                          icon: Icons.apartment_outlined,
                          label: 'Properti Hotel',
                          aktif: menuAktif == 'Properti Hotel',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Properti Hotel',
                            builder: (_) => const PropertiHotelScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('hotel_kamar')))
                        _ItemMenu(
                          icon: Icons.meeting_room_outlined,
                          label: 'Kamar & Tipe Kamar',
                          aktif: menuAktif == 'Kamar & Tipe Kamar',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kamar & Tipe Kamar',
                            builder: (_) => const KamarHotelScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('hotel_reservasi')))
                        _ItemMenu(
                          icon: Icons.event_available_outlined,
                          label: 'Tamu & Reservasi',
                          aktif: menuAktif == 'Tamu & Reservasi',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Tamu & Reservasi',
                            builder: (_) => const ReservasiHotelScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('hotel_checkin') ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('hotel_folio')))
                        _ItemMenu(
                          icon: Icons.luggage_outlined,
                          label: 'Check-in / Check-out',
                          aktif: menuAktif == 'Check-in / Check-out',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Check-in / Check-out',
                            builder: (_) => const ResepsionisHotelScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance
                                  .bolehMenuVarianBaru('hotel_tiket_dapur')))
                        _ItemMenu(
                          icon: Icons.restaurant_outlined,
                          label: 'Tiket Dapur',
                          aktif: menuAktif == 'Tiket Dapur',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Tiket Dapur',
                            builder: (_) => const TiketDapurScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance.bolehMenuVarianBaru(
                                  'hotel_kontrak_pemilik')))
                        _ItemMenu(
                          icon: Icons.handshake_outlined,
                          label: 'Kontrak Pemilik',
                          aktif: menuAktif == 'Kontrak Pemilik',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kontrak Pemilik',
                            builder: (_) => const KontrakPemilikScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isMitraInap &&
                          (Sesi.instance.isAdmin ||
                              Sesi.instance.bolehMenuVarianBaru(
                                  'hotel_laporan_pemilik')))
                        _ItemMenu(
                          icon: Icons.receipt_long_outlined,
                          label: 'Laporan Pemilik',
                          aktif: menuAktif == 'Laporan Pemilik',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Laporan Pemilik',
                            builder: (_) => const LaporanPemilikScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales)
                        _ItemMenu(
                          icon: Icons.storefront_outlined,
                          label: 'Beranda Inventory & Sales',
                          aktif: menuAktif == 'Beranda Inventory & Sales',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Beranda Inventory & Sales',
                            builder: (_) => const BerandaInventorySalesScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('master_supplier'))
                        _ItemMenu(
                          icon: Icons.local_shipping_outlined,
                          label: 'Master Supplier',
                          aktif: menuAktif == 'Master Supplier',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Master Supplier',
                            builder: (_) => const MasterSupplierScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('master_customer'))
                        _ItemMenu(
                          icon: Icons.people_alt_outlined,
                          label: 'Master Customer',
                          aktif: menuAktif == 'Master Customer',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Master Customer',
                            builder: (_) => const MasterCustomerScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('master_sales') &&
                          (Sesi.instance.isPemilikSalesInventory ||
                              Sesi.instance.isSalesKeliling))
                        _ItemMenu(
                          icon: Icons.badge_outlined,
                          label: 'Master Sales',
                          aktif: menuAktif == 'Master Sales',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Master Sales',
                            builder: (_) => const MasterSalesScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('persediaan'))
                        _ItemMenu(
                          icon: Icons.warehouse_outlined,
                          label: 'Persediaan & Kartu Stok',
                          aktif: menuAktif == 'Persediaan & Kartu Stok',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Persediaan & Kartu Stok',
                            builder: (_) => const PersediaanScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('harga'))
                        _ItemMenu(
                          icon: Icons.price_change_outlined,
                          label: 'Master & Analisis Harga',
                          aktif: menuAktif == 'Master & Analisis Harga',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Master & Analisis Harga',
                            builder: (_) => const HargaScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('hutang'))
                        _ItemMenu(
                          icon: Icons.account_balance_outlined,
                          label: 'Hutang Supplier (AP)',
                          aktif: menuAktif == 'Hutang Supplier (AP)',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Hutang Supplier (AP)',
                            builder: (_) => const HutangSupplierScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('penjualan_sales') &&
                          (Sesi.instance.isPemilikSalesInventory ||
                              Sesi.instance.isSalesKeliling))
                        _ItemMenu(
                          icon: Icons.shopping_cart_checkout,
                          label: 'Penjualan Sales',
                          aktif: menuAktif == 'Penjualan Sales',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Penjualan Sales',
                            builder: (_) => const PenjualanSalesScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('piutang'))
                        _ItemMenu(
                          icon: Icons.request_quote_outlined,
                          label: 'Piutang Customer (AR)',
                          aktif: menuAktif == 'Piutang Customer (AR)',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Piutang Customer (AR)',
                            builder: (_) => const PiutangScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('surat_perintah_sales') &&
                          (Sesi.instance.isPemilikSalesInventory ||
                              Sesi.instance.isSalesKeliling))
                        _ItemMenu(
                          icon: Icons.assignment_outlined,
                          label: 'Surat Perintah Sales',
                          aktif: menuAktif == 'Surat Perintah Sales',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Surat Perintah Sales',
                            builder: (_) => const SpjScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('nota_sales') &&
                          (Sesi.instance.isPemilikSalesInventory ||
                              Sesi.instance.isSalesKeliling))
                        _ItemMenu(
                          icon: Icons.route_outlined,
                          label: 'Sesi Nota Sales',
                          aktif: menuAktif == 'Sesi Nota Sales',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Sesi Nota Sales',
                            builder: (_) => const NotaSalesScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('kas_jurnal'))
                        _ItemMenu(
                          icon: Icons.menu_book_outlined,
                          label: 'Kas & Jurnal',
                          aktif: menuAktif == 'Kas & Jurnal',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kas & Jurnal',
                            builder: (_) => const KasJurnalScreen(),
                          ),
                        ),
                      if (AppProductProfile.aktif.isInventorySales &&
                          Sesi.instance.bolehMenuIs('laba_rugi'))
                        _ItemMenu(
                          icon: Icons.stacked_line_chart,
                          label: 'Laba Rugi',
                          aktif: menuAktif == 'Laba Rugi',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Laba Rugi',
                            builder: (_) => const LabaRugiScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('kasir'))
                        _ItemMenu(
                          icon: Icons.point_of_sale,
                          label: 'Kasir',
                          aktif: menuAktif == 'Kasir',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kasir',
                            builder: (_) => const KasirScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('ringkasan'))
                        _ItemMenu(
                          icon: Icons.bar_chart,
                          label: 'Ringkasan',
                          aktif: menuAktif == 'Ringkasan',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Ringkasan',
                            builder: (_) => const RingkasanScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('pesanan'))
                        _ItemMenu(
                          icon: Icons.receipt_long,
                          label: 'Pesanan',
                          aktif: menuAktif == 'Pesanan',
                          badge: PesananPoller.instance.jumlahBaru,
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Pesanan',
                            builder: (_) => const PesananScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('anggota'))
                        _ItemMenu(
                          icon: Icons.people_outline,
                          label: 'Customer/Anggota',
                          aktif: menuAktif == 'Customer/Anggota',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Customer/Anggota',
                            builder: (_) => const AnggotaScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('produk'))
                        _ItemMenu(
                          icon: Icons.inventory_2_outlined,
                          label: 'Produk',
                          aktif: menuAktif == 'Produk',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Produk',
                            builder: (_) => const ProdukScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('produk'))
                        _ItemMenu(
                          icon: Icons.category_outlined,
                          label: 'Jenis Produk',
                          aktif: menuAktif == 'Jenis Produk',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Jenis Produk',
                            builder: (_) => const JenisProdukScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenuVarianBaru('grup_produk'))
                        _ItemMenu(
                          icon: Icons.workspaces_outline,
                          label: 'Grup Produk',
                          aktif: menuAktif == 'Grup Produk',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Grup Produk',
                            builder: (_) => const GrupProdukScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('stokopname'))
                        _ItemMenu(
                          icon: Icons.fact_check_outlined,
                          label: 'Stok Opname',
                          aktif: menuAktif == 'Stok Opname',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Stok Opname',
                            builder: (_) => const StokOpnameScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('stokopname'))
                        _ItemMenu(
                          icon: Icons.event_busy_outlined,
                          label: 'Kedaluwarsa',
                          aktif: menuAktif == 'Kedaluwarsa',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kedaluwarsa',
                            builder: (_) => const KedaluwarsaScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('mutasistokantaroutlet'))
                        _ItemMenu(
                          icon: Icons.compare_arrows,
                          label: 'Mutasi Antar Outlet',
                          aktif: menuAktif == 'Mutasi Antar Outlet',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Mutasi Antar Outlet',
                            builder: (_) => const MutasiAntarOutletScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('kulakan'))
                        _ItemMenu(
                          icon: Icons.local_shipping_outlined,
                          label: 'Kulakan',
                          aktif: menuAktif == 'Kulakan',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kulakan',
                            builder: (_) => const KulakanScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('penyedia'))
                        _ItemMenu(
                          icon: Icons.local_shipping_outlined,
                          label: 'Supplier (Penyedia)',
                          aktif: menuAktif == 'Supplier (Penyedia)',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Supplier (Penyedia)',
                            builder: (_) => const SupplierScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('diskon'))
                        _ItemMenu(
                          icon: Icons.sell_outlined,
                          label: 'Aturan Diskon',
                          aktif: menuAktif == 'Aturan Diskon',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Aturan Diskon',
                            builder: (_) => const DiskonScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('pembayaran'))
                        _ItemMenu(
                          icon: Icons.payments_outlined,
                          label: 'Cara Pembayaran',
                          aktif: menuAktif == 'Cara Pembayaran',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Cara Pembayaran',
                            builder: (_) => const CaraBayarScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('returpenjualan'))
                        _ItemMenu(
                          icon: Icons.assignment_return_outlined,
                          label: 'Retur Penjualan',
                          aktif: menuAktif == 'Retur Penjualan',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Retur Penjualan',
                            builder: (_) => const ReturPenjualanScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('riwayatpenjualan'))
                        _ItemMenu(
                          icon: Icons.history,
                          label: 'Riwayat Penjualan',
                          aktif: menuAktif == 'Riwayat Penjualan',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Riwayat Penjualan',
                            builder: (_) => const RiwayatPenjualanScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('laporantransaksi'))
                        _ItemMenu(
                          icon: Icons.assessment_outlined,
                          label: 'Laporan Transaksi',
                          aktif: menuAktif == 'Laporan Transaksi',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Laporan Transaksi',
                            builder: (_) => const LaporanTransaksiScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('laporan'))
                        _ItemMenu(
                          icon: Icons.folder_outlined,
                          label: 'Laporan-Laporan',
                          aktif: menuAktif == 'Laporan-Laporan',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Laporan-Laporan',
                            builder: (_) => const LaporanScreen(),
                          ),
                        ),
                      // "Akuntansi" adalah GRUP yang bisa dibuka-tutup (bawaan: tertutup).
                      // Gerbangnya memakai bolehMenuVarianBaru (kunci hilang = TIDAK boleh),
                      // karena menu ini fail-closed di server: bawaannya hanya terbuka untuk
                      // peran keu (Keuangan) dan am (Admin), selain itu harus dinyalakan admin.
                      // Kunci induknya tetap 'laporankeuangan' supaya hak akses peran yang
                      // sudah ada tidak berubah arti; tiap submenu punya kuncinya sendiri
                      // sehingga admin bisa membatasi per layar lewat grid CRUD peran.
                      if (Sesi.instance.bolehMenuVarianBaru('laporankeuangan'))
                        _GrupMenu(
                          icon: Icons.account_balance_outlined,
                          label: 'Akuntansi',
                          adaYangAktif: const [
                            'Draft Jurnal',
                            'Jurnal Umum',
                            'Posting HPP',
                            'Posting Penjualan',
                            'Kode Akun',
                            'Grup Akun',
                            'Jenis Transaksi',
                            'Bank',
                            'Saldo Awal (Neraca Awal)',
                            'Jurnal Penyesuaian Berkala',
                            'Tutup Buku (Laba Ditahan)',
                            'Posting Kulakan',
                            'Posting Bayar Hutang',
                            'Posting Terima Piutang',
                            'Anggaran (RAB Bulanan)',
                            'Laporan-Laporan Keuangan',
                          ].contains(menuAktif),
                          anak: [
                            if (Sesi.instance.bolehMenuVarianBaru('draft_jurnal'))
                              _ItemMenu(
                                icon: Icons.fact_check_outlined,
                                label: 'Draft Jurnal',
                                aktif: menuAktif == 'Draft Jurnal',
                                onTap: () => _pindahMenu(context,
                                    label: 'Draft Jurnal',
                                    builder: (_) => const DraftJurnalScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('jurnal_umum'))
                              _ItemMenu(
                                icon: Icons.edit_note,
                                label: 'Jurnal Umum',
                                aktif: menuAktif == 'Jurnal Umum',
                                onTap: () => _pindahMenu(context,
                                    label: 'Jurnal Umum',
                                    builder: (_) => const JurnalUmumScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('posting_hpp'))
                              _ItemMenu(
                                icon: Icons.inventory_2_outlined,
                                label: 'Posting HPP',
                                aktif: menuAktif == 'Posting HPP',
                                onTap: () => _pindahMenu(
                                  context,
                                  label: 'Posting HPP',
                                  builder: (_) => const LaporanScreen(
                                    aksiKatalog: 'laporan_keuangan_katalog',
                                    judul: 'Posting HPP',
                                    subjudul:
                                        'Membukukan harga pokok penjualan ke buku besar',
                                    bukaPosting: 'posting_hpp',
                                  ),
                                ),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('posting_penjualan'))
                              _ItemMenu(
                                icon: Icons.point_of_sale_outlined,
                                label: 'Posting Penjualan',
                                aktif: menuAktif == 'Posting Penjualan',
                                onTap: () => _pindahMenu(
                                  context,
                                  label: 'Posting Penjualan',
                                  builder: (_) => const LaporanScreen(
                                    aksiKatalog: 'laporan_keuangan_katalog',
                                    judul: 'Posting Penjualan',
                                    subjudul:
                                        'Membukukan penjualan kasir ke buku besar',
                                    bukaPosting: 'posting_penjualan',
                                  ),
                                ),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('kode_akun'))
                              _ItemMenu(
                                icon: Icons.account_tree_outlined,
                                label: 'Kode Akun',
                                aktif: menuAktif == 'Kode Akun',
                                onTap: () => _pindahMenu(context,
                                    label: 'Kode Akun',
                                    builder: (_) => _halamanAkuntansi(
                                        'Kode Akun',
                                        const KodeAkunScreen(tabAwal: 0))),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('grup_akun'))
                              _ItemMenu(
                                icon: Icons.workspaces_outline,
                                label: 'Grup Akun',
                                aktif: menuAktif == 'Grup Akun',
                                onTap: () => _pindahMenu(context,
                                    label: 'Grup Akun',
                                    builder: (_) => _halamanAkuntansi(
                                        'Grup Akun',
                                        const KodeAkunScreen(tabAwal: 4))),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('jenis_transaksi'))
                              _ItemMenu(
                                icon: Icons.swap_horiz,
                                label: 'Jenis Transaksi',
                                aktif: menuAktif == 'Jenis Transaksi',
                                onTap: () => _pindahMenu(context,
                                    label: 'Jenis Transaksi',
                                    builder: (_) => _halamanAkuntansi(
                                        'Jenis Transaksi',
                                        const KodeAkunScreen(tabAwal: 3))),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('bank_akun'))
                              _ItemMenu(
                                icon: Icons.account_balance,
                                label: 'Bank',
                                aktif: menuAktif == 'Bank',
                                onTap: () => _pindahMenu(context,
                                    label: 'Bank',
                                    builder: (_) => _halamanAkuntansi(
                                        'Bank',
                                        const KodeAkunScreen(tabAwal: 2))),
                              ),
                            // Enam layar berikut sebelumnya hanya tab di dalam layar
                            // Laporan Keuangan; kini tiap layar punya kunci menunya
                            // sendiri di EbisnisMenuKatalog sehingga admin bisa
                            // membatasinya per peran lewat grid CRUD TbmroleAction.
                            if (Sesi.instance.bolehMenuVarianBaru('saldo_awal_akun'))
                            _ItemMenu(
                              icon: Icons.play_circle_outline,
                              label: 'Saldo Awal (Neraca Awal)',
                              aktif: menuAktif == 'Saldo Awal (Neraca Awal)',
                              onTap: () => _pindahMenu(context,
                                  label: 'Saldo Awal (Neraca Awal)',
                                  builder: (_) => _halamanSiklus(
                                      'Saldo Awal (Neraca Awal)', 0)),
                            ),
                            if (Sesi.instance.bolehMenuVarianBaru('jurnal_penyesuaian'))
                            _ItemMenu(
                              icon: Icons.rule_folder_outlined,
                              label: 'Jurnal Penyesuaian Berkala',
                              aktif: menuAktif == 'Jurnal Penyesuaian Berkala',
                              onTap: () => _pindahMenu(context,
                                  label: 'Jurnal Penyesuaian Berkala',
                                  builder: (_) => _halamanSiklus(
                                      'Jurnal Penyesuaian Berkala', 1)),
                            ),
                            if (Sesi.instance.bolehMenuVarianBaru('tutup_buku'))
                            _ItemMenu(
                              icon: Icons.lock_outline,
                              label: 'Tutup Buku (Laba Ditahan)',
                              aktif: menuAktif == 'Tutup Buku (Laba Ditahan)',
                              onTap: () => _pindahMenu(context,
                                  label: 'Tutup Buku (Laba Ditahan)',
                                  builder: (_) => _halamanSiklus(
                                      'Tutup Buku (Laba Ditahan)', 2)),
                            ),
                            if (Sesi.instance.bolehMenuVarianBaru('posting_kulakan'))
                            _ItemMenu(
                              icon: Icons.local_shipping_outlined,
                              label: 'Posting Kulakan',
                              aktif: menuAktif == 'Posting Kulakan',
                              onTap: () => _pindahMenu(
                                context,
                                label: 'Posting Kulakan',
                                builder: (_) => const LaporanScreen(
                                  aksiKatalog: 'laporan_keuangan_katalog',
                                  judul: 'Posting Kulakan',
                                  subjudul:
                                      'Membukukan pembelian barang toko (persediaan & utang supplier)',
                                  bukaPosting: 'posting_kulakan',
                                ),
                              ),
                            ),
                            if (Sesi.instance.bolehMenuVarianBaru('posting_bayar_hutang'))
                            _ItemMenu(
                              icon: Icons.payments_outlined,
                              label: 'Posting Bayar Hutang',
                              aktif: menuAktif == 'Posting Bayar Hutang',
                              onTap: () => _pindahMenu(
                                context,
                                label: 'Posting Bayar Hutang',
                                builder: (_) => const LaporanScreen(
                                  aksiKatalog: 'laporan_keuangan_katalog',
                                  judul: 'Posting Bayar Hutang',
                                  subjudul:
                                      'Membukukan pembayaran hutang ke supplier toko',
                                  bukaPosting: 'posting_bayar_hutang',
                                ),
                              ),
                            ),
                            if (Sesi.instance.bolehMenuVarianBaru('posting_terima_piutang'))
                            _ItemMenu(
                              icon: Icons.savings_outlined,
                              label: 'Posting Terima Piutang',
                              aktif: menuAktif == 'Posting Terima Piutang',
                              onTap: () => _pindahMenu(
                                context,
                                label: 'Posting Terima Piutang',
                                builder: (_) => const LaporanScreen(
                                  aksiKatalog: 'laporan_keuangan_katalog',
                                  judul: 'Posting Terima Piutang',
                                  subjudul:
                                      'Membukukan penerimaan piutang dari pelanggan toko',
                                  bukaPosting: 'posting_terima_piutang',
                                ),
                              ),
                            ),
                            // Anggaran/RAB bulanan: satu layar bertab (Rencana Bulanan,
                            // Realisasi, Penggunaan Anggaran) -- padanan empat layar ZK.
                            if (Sesi.instance.bolehMenuVarianBaru('anggaran'))
                            _ItemMenu(
                              icon: Icons.savings_outlined,
                              label: 'Anggaran (RAB Bulanan)',
                              aktif: menuAktif == 'Anggaran (RAB Bulanan)',
                              onTap: () => _pindahMenu(
                                context,
                                label: 'Anggaran (RAB Bulanan)',
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('Anggaran (RAB Bulanan)')),
                                  body: const AnggaranScreen(),
                                ),
                              ),
                            ),
                            _ItemMenu(
                              icon: Icons.folder_open_outlined,
                              label: 'Laporan-Laporan',
                              aktif: menuAktif == 'Laporan-Laporan Keuangan',
                              onTap: () => _pindahMenu(
                                context,
                                label: 'Laporan-Laporan Keuangan',
                                builder: (_) => const LaporanScreen(
                                  aksiKatalog: 'laporan_keuangan_katalog',
                                  judul: 'Laporan Keuangan',
                                  subjudul:
                                      'Neraca, Laba Rugi, Arus Kas, Buku Besar, Piutang & lainnya',
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (Sesi.instance.bolehMenu('riwayatsinkronisasi'))
                        _ItemMenu(
                          icon: Icons.sync,
                          label: 'Riwayat Sinkronisasi',
                          aktif: menuAktif == 'Riwayat Sinkronisasi',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Riwayat Sinkronisasi',
                            builder: (_) => const RiwayatSinkronisasiScreen(),
                          ),
                        ),
                      // Grup "Keuangan" (2026-08-21): enam modul alur kas dari layar ZK
                      // akunting, plus Bayar Pajak & Pembayaran Vendor yang dipindah ke
                      // sini dari grup Pengadaan. Kunci menu keduanya sengaja TIDAK
                      // diubah supaya hak akses peran yang sudah ada tetap berlaku.
                      if ([
                        'uang_muka',
                        'pj_uang_muka',
                        'kas_besar',
                        'pj_kas_besar',
                        'kas_kecil',
                        'penggantian_kas_kecil',
                        'pengadaan_pajak',
                        'pengadaan_dpc',
                      ].any(Sesi.instance.bolehMenuVarianBaru))
                        _GrupMenu(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Keuangan',
                          adaYangAktif: const [
                            'Uang Muka (Cash Advance)',
                            'Pertanggungjawaban Uang Muka',
                            'Kas Besar',
                            'Pertanggungjawaban Kas Besar',
                            'Kas Kecil',
                            'Penggantian Kas Kecil (Reimbursement)',
                            'Bayar Pajak',
                            'Pembayaran Vendor',
                          ].contains(menuAktif),
                          anak: [
                            if (Sesi.instance.bolehMenuVarianBaru('uang_muka'))
                              _ItemMenu(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Uang Muka (Cash Advance)',
                                aktif: menuAktif == 'Uang Muka (Cash Advance)',
                                onTap: () => _pindahMenu(context,
                                    label: 'Uang Muka (Cash Advance)',
                                    builder: (_) => const UangMukaScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pj_uang_muka'))
                              _ItemMenu(
                                icon: Icons.fact_check_outlined,
                                label: 'Pertanggungjawaban Uang Muka',
                                aktif: menuAktif == 'Pertanggungjawaban Uang Muka',
                                onTap: () => _pindahMenu(context,
                                    label: 'Pertanggungjawaban Uang Muka',
                                    builder: (_) => const PjUangMukaScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('kas_besar'))
                              _ItemMenu(
                                icon: Icons.savings_outlined,
                                label: 'Kas Besar',
                                aktif: menuAktif == 'Kas Besar',
                                onTap: () => _pindahMenu(context,
                                    label: 'Kas Besar',
                                    builder: (_) => const KasBesarScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pj_kas_besar'))
                              _ItemMenu(
                                icon: Icons.assignment_turned_in_outlined,
                                label: 'Pertanggungjawaban Kas Besar',
                                aktif: menuAktif == 'Pertanggungjawaban Kas Besar',
                                onTap: () => _pindahMenu(context,
                                    label: 'Pertanggungjawaban Kas Besar',
                                    builder: (_) => const PjKasBesarScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('kas_kecil'))
                              _ItemMenu(
                                icon: Icons.receipt_long_outlined,
                                label: 'Kas Kecil',
                                aktif: menuAktif == 'Kas Kecil',
                                onTap: () => _pindahMenu(context,
                                    label: 'Kas Kecil',
                                    builder: (_) => const KasKecilScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('penggantian_kas_kecil'))
                              _ItemMenu(
                                icon: Icons.autorenew,
                                label: 'Penggantian Kas Kecil (Reimbursement)',
                                aktif: menuAktif == 'Penggantian Kas Kecil (Reimbursement)',
                                onTap: () => _pindahMenu(context,
                                    label: 'Penggantian Kas Kecil (Reimbursement)',
                                    builder: (_) => const PenggantianKasKecilScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('dana_talangan'))
                              _ItemMenu(
                                icon: Icons.handshake_outlined,
                                label: 'Dana Talangan',
                                aktif: menuAktif == 'Dana Talangan',
                                onTap: () => _pindahMenu(context,
                                    label: 'Dana Talangan',
                                    builder: (_) => const DanaTalanganScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_pajak'))
                              _ItemMenu(
                                icon: Icons.account_balance,
                                label: 'Bayar Pajak',
                                aktif: menuAktif == 'Bayar Pajak',
                                onTap: () => _pindahMenu(context,
                                    label: 'Bayar Pajak',
                                    builder: (_) => const PengadaanPajakScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_dpc'))
                              _ItemMenu(
                                icon: Icons.payments_outlined,
                                label: 'Pembayaran Vendor',
                                aktif: menuAktif == 'Pembayaran Vendor',
                                onTap: () => _pindahMenu(context,
                                    label: 'Pembayaran Vendor',
                                    builder: (_) => const PengadaanBayarScreen()),
                              ),
                          ],
                        ),
                      // "Pengadaan" adalah GRUP yang bisa dibuka-tutup (bawaan: tertutup),
                      // mengikuti permintaan pemilik produk. Tiap tahap punya kunci menunya
                      // sendiri sehingga admin dapat membatasi per layar lewat grid CRUD peran.
                      if (Sesi.instance.bolehMenuVarianBaru('pengadaan_pr') ||
                          Sesi.instance.bolehMenuVarianBaru('pengadaan_po') ||
                          Sesi.instance.bolehMenuVarianBaru('pengadaan_bast') ||
                          Sesi.instance.bolehMenuVarianBaru('pengadaan_tagihan') ||
                          Sesi.instance.bolehMenuVarianBaru('pengadaan_bdp'))
                        _GrupMenu(
                          icon: Icons.assignment_outlined,
                          label: 'Pengadaan',
                          adaYangAktif: const [
                            'Permintaan Pembelian (PR)',
                            'Pemesanan Pembelian (PO)',
                            'Penerimaan Barang (BAST)',
                            'Terima Tagihan Vendor',
                            'Barang Dalam Proses',
                          ].contains(menuAktif),
                          anak: [
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_pr'))
                              _ItemMenu(
                                icon: Icons.assignment_outlined,
                                label: 'Permintaan Pembelian (PR)',
                                aktif: menuAktif == 'Permintaan Pembelian (PR)',
                                onTap: () => _pindahMenu(context,
                                    label: 'Permintaan Pembelian (PR)',
                                    builder: (_) => const PengadaanPrScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_po'))
                              _ItemMenu(
                                icon: Icons.receipt_long_outlined,
                                label: 'Pemesanan Pembelian (PO)',
                                aktif: menuAktif == 'Pemesanan Pembelian (PO)',
                                onTap: () => _pindahMenu(context,
                                    label: 'Pemesanan Pembelian (PO)',
                                    builder: (_) => const PengadaanPoScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_bast'))
                              _ItemMenu(
                                icon: Icons.inventory_2_outlined,
                                label: 'Penerimaan Barang (BAST)',
                                aktif: menuAktif == 'Penerimaan Barang (BAST)',
                                onTap: () => _pindahMenu(context,
                                    label: 'Penerimaan Barang (BAST)',
                                    builder: (_) => const PengadaanBastScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_tagihan'))
                              _ItemMenu(
                                icon: Icons.request_quote_outlined,
                                label: 'Terima Tagihan Vendor',
                                aktif: menuAktif == 'Terima Tagihan Vendor',
                                onTap: () => _pindahMenu(context,
                                    label: 'Terima Tagihan Vendor',
                                    builder: (_) => const PengadaanTagihanScreen()),
                              ),
                            if (Sesi.instance.bolehMenuVarianBaru('pengadaan_bdp'))
                              _ItemMenu(
                                icon: Icons.local_shipping_outlined,
                                label: 'Barang Dalam Proses',
                                aktif: menuAktif == 'Barang Dalam Proses',
                                onTap: () => _pindahMenu(context,
                                    label: 'Barang Dalam Proses',
                                    builder: (_) => const PengadaanBdpScreen()),
                              ),
                          ],
                        ),
                      if (Sesi.instance.bolehMenu('logerror'))
                        _ItemMenu(
                          icon: Icons.error_outline,
                          label: 'Log Error',
                          aktif: menuAktif == 'Log Error',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Log Error',
                            builder: (_) => const LogErrorScreen(),
                          ),
                        ),
                      if (Sesi.instance.bolehMenu('konfigurasi'))
                        _ItemMenu(
                          icon: Icons.settings_outlined,
                          label: 'Konfigurasi',
                          aktif: menuAktif == 'Konfigurasi',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Konfigurasi',
                            builder: (_) => const KonfigurasiScreen(),
                          ),
                        ),
                      _ItemMenu(
                        icon: Icons.desktop_windows_outlined,
                        label: 'Layar Pelanggan',
                        aktif: menuAktif == 'Layar Pelanggan',
                        onTap: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          bukaLayarPelanggan(context);
                        },
                      ),
                      if (Sesi.instance.isAdmin)
                        _ItemMenu(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Hak Akses',
                          aktif: menuAktif == 'Hak Akses',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Hak Akses',
                            builder: (_) => const HakAksesScreen(),
                          ),
                        ),
                      if (Sesi.instance.isAdmin)
                        _ItemMenu(
                          icon: Icons.storefront_outlined,
                          label: 'Kelola Toko',
                          aktif: menuAktif == 'Kelola Toko',
                          onTap: () => _pindahMenu(
                            context,
                            label: 'Kelola Toko',
                            builder: (_) => const TokoKelolaScreen(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AppVersionLabel(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grup menu yang bisa dibuka-tutup (mis. "Akuntansi").
///
/// Bawaannya TERTUTUP supaya daftar menu utama tetap ringkas; terbuka sendiri bila salah
/// satu submenunya sedang aktif agar pengguna tidak kehilangan posisinya setelah pindah
/// halaman.
class _GrupMenu extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool adaYangAktif;
  final List<Widget> anak;
  const _GrupMenu({
    required this.icon,
    required this.label,
    required this.anak,
    this.adaYangAktif = false,
  });

  @override
  State<_GrupMenu> createState() => _GrupMenuState();
}

class _GrupMenuState extends State<_GrupMenu> {
  late bool _terbuka = widget.adaYangAktif;

  @override
  void didUpdateWidget(covariant _GrupMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.adaYangAktif && !_terbuka) {
      _terbuka = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final warnaAktif = Theme.of(context).colorScheme.primary;
    final warnaTeks =
        widget.adaYangAktif ? warnaAktif : AppColors.textPrimaryOf(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: Icon(widget.icon, color: warnaTeks),
        title: Text(widget.label,
            style: TextStyle(
                color: warnaTeks,
                fontWeight:
                    widget.adaYangAktif ? FontWeight.w700 : FontWeight.normal)),
        trailing: Icon(_terbuka ? Icons.expand_less : Icons.expand_more,
            color: warnaTeks),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => setState(() => _terbuka = !_terbuka),
      ),
      if (_terbuka)
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: widget.anak),
        ),
    ]);
  }
}

class _ItemMenu extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool aktif;
  final VoidCallback? onTap;
  final ValueNotifier<int>? badge;
  const _ItemMenu(
      {required this.icon,
      required this.label,
      this.aktif = false,
      this.onTap,
      this.badge});

  @override
  Widget build(BuildContext context) {
    final warnaAktif = Theme.of(context).colorScheme.primary;
    final warnaTeks = aktif ? warnaAktif : AppColors.textPrimaryOf(context);
    final iconWidget = Icon(icon, color: warnaTeks);
    return ListTile(
      leading: badge == null
          ? iconWidget
          : ValueListenableBuilder<int>(
              valueListenable: badge!,
              builder: (context, jumlah, _) => Badge(
                  label: Text('$jumlah'),
                  isLabelVisible: jumlah > 0,
                  child: iconWidget),
            ),
      title: Text(label, style: TextStyle(color: warnaTeks)),
      selected: aktif,
      selectedTileColor: AppColors.latarLembut(warnaAktif),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}
