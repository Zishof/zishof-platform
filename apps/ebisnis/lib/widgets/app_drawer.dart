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
import '../screens/laporan_transaksi_screen.dart';
import '../screens/ringkasan_screen.dart';
import '../screens/diskon_screen.dart';
import '../screens/kulakan_screen.dart';
import '../screens/konfigurasi_screen.dart';
import '../screens/log_error_screen.dart';
import '../screens/retur_penjualan_screen.dart';
import '../screens/riwayat_penjualan_screen.dart';
import '../screens/riwayat_sinkronisasi_screen.dart';
import '../screens/laporan_screen.dart';
import '../screens/hak_akses_screen.dart';
import '../screens/inventory_sales/beranda_is_screen.dart';
import '../screens/inventory_sales/master_supplier_screen.dart';
import '../screens/inventory_sales/master_customer_screen.dart';
import '../screens/inventory_sales/master_sales_screen.dart';
import '../screens/inventory_sales/persediaan_screen.dart';
import '../screens/inventory_sales/harga_screen.dart';
import '../product_profile.dart';

/// Menu navigasi utama -- padanan sidebar kiri versi Electron (Kasir/Ringkasan/
/// Pesanan/Customer-Anggota/Produk/Stok Opname/Kulakan/Aturan Diskon/Laporan
/// Transaksi/Laporan-Laporan/Riwayat Sinkronisasi/Log Error/Konfigurasi).
/// Layar yang belum dibangun ditandai "Segera Hadir" (dinonaktifkan) -- lihat
/// task #182-189 utk urutan pengerjaan, jangan hapus entrinya supaya progres
/// tetap terlihat sambil layar-layar itu menyusul satu per satu.
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
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1E3A5F)),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  Sesi.instance.tokoNama.isEmpty
                      ? AppVariant.namaAplikasi
                      : Sesi.instance.tokoNama,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: menuAktifNotifier,
                builder: (context, _, __) => ListView(
                  padding: EdgeInsets.zero,
                  children: [
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
                        Sesi.instance.bolehMenuIs('master_sales'))
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
