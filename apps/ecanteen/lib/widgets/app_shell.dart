import 'package:flutter/material.dart';

import '../app_variant.dart';
import '../services/keranjang.dart';
import '../services/sesi.dart';
import '../theme/app_colors.dart';
import 'format.dart';

/// Menu yang tersedia di cangkang aplikasi anggota.
enum MenuAnggota {
  belanja,
  keranjang,
  pesanan,
  riwayat,
  isiSaldo,
  bayarQr,
  ringkasan,
}

class _ItemMenu {
  final MenuAnggota menu;
  final IconData ikon;
  final String label;
  const _ItemMenu(this.menu, this.ikon, this.label);
}

const _daftarMenu = <_ItemMenu>[
  _ItemMenu(MenuAnggota.belanja, Icons.storefront_outlined, 'Belanja'),
  _ItemMenu(MenuAnggota.keranjang, Icons.shopping_cart_outlined, 'Keranjang'),
  _ItemMenu(MenuAnggota.pesanan, Icons.receipt_long_outlined, 'Pesanan'),
  _ItemMenu(MenuAnggota.riwayat, Icons.history, 'Riwayat'),
  _ItemMenu(
      MenuAnggota.isiSaldo, Icons.account_balance_wallet_outlined, 'Isi Saldo'),
  _ItemMenu(MenuAnggota.bayarQr, Icons.qr_code_scanner, 'Bayar QR'),
  _ItemMenu(MenuAnggota.ringkasan, Icons.insights_outlined, 'Ringkasan'),
];

/// Cangkang halaman aplikasi anggota.
///
/// Tata letak dan temanya sengaja mengikuti POS Desktop: sidebar navy di kiri,
/// topbar berisi identitas pengguna, lalu judul halaman dan kontennya. Pada
/// layar sempit sidebar berubah menjadi Drawer supaya konten tetap lega.
class AppShell extends StatelessWidget {
  final MenuAnggota menuAktif;
  final String judul;
  final String? subjudul;
  final Widget child;
  final List<Widget> aksi;
  final Widget? floatingActionButton;

  /// Dipanggil saat item menu ditekan. Cangkang tidak mengatur navigasi
  /// sendiri supaya tiap layar bebas menentukan cara berpindah (push vs
  /// pushReplacement).
  final void Function(BuildContext context, MenuAnggota menu) onPilihMenu;

  const AppShell({
    super.key,
    required this.menuAktif,
    required this.judul,
    required this.child,
    required this.onPilihMenu,
    this.subjudul,
    this.aksi = const [],
    this.floatingActionButton,
  });

  static const double _lebarSidebar = 236;
  static const double _batasLebar = 900;

  @override
  Widget build(BuildContext context) {
    final lebar = MediaQuery.sizeOf(context).width;
    final sidebarMenetap = lebar >= _batasLebar;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      drawer: sidebarMenetap
          ? null
          : Drawer(
              backgroundColor: AppColors.sidebarBg,
              child: _Sidebar(
                  menuAktif: menuAktif,
                  onPilih: (m) {
                    Navigator.of(context).pop();
                    onPilihMenu(context, m);
                  }),
            ),
      appBar: sidebarMenetap
          ? null
          : AppBar(
              backgroundColor: AppColors.sidebarBg,
              foregroundColor: Colors.white,
              title: Text(judul),
              actions: aksi,
            ),
      // Di ponsel keranjang sudah punya tempat di bilah bawah (berikut
      // penanda jumlahnya), jadi tombol mengambang dimatikan supaya tidak
      // menumpuk di sudut yang sama.
      floatingActionButton: sidebarMenetap ? floatingActionButton : null,
      // Di ponsel, empat menu paling sering dipakai naik ke bilah bawah --
      // pola yang lazim untuk aplikasi belanja. Sisanya tetap di laci.
      bottomNavigationBar: sidebarMenetap ? null : _bilahBawah(context),
      body: Row(
        children: [
          if (sidebarMenetap)
            SizedBox(
              width: _lebarSidebar,
              child: _Sidebar(
                  menuAktif: menuAktif,
                  onPilih: (m) => onPilihMenu(context, m)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sidebarMenetap) _Topbar(aksi: aksi),
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(20, sidebarMenetap ? 20 : 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sidebarMenetap)
                        Text(judul,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                      if (subjudul != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subjudul!,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13)),
                        ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _menuBawah = <MenuAnggota>[
    MenuAnggota.belanja,
    MenuAnggota.keranjang,
    MenuAnggota.pesanan,
    MenuAnggota.riwayat,
  ];

  Widget _bilahBawah(BuildContext context) {
    final indeks = _menuBawah.indexOf(menuAktif);
    return NavigationBar(
      height: 62,
      backgroundColor: AppColors.cardBg,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      // Menu yang sedang aktif tapi TIDAK ada di bilah bawah (mis. Isi Saldo)
      // tetap valid; indeks 0 dipakai sekadar supaya tidak ada yang tersorot
      // keliru, dan penyorotannya dimatikan lewat warna indikator.
      selectedIndex: indeks < 0 ? 0 : indeks,
      onDestinationSelected: (i) => onPilihMenu(context, _menuBawah[i]),
      destinations: [
        const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Belanja'),
        NavigationDestination(
          icon: Badge.count(
            count: Keranjang.instance.jumlahItem,
            isLabelVisible: Keranjang.instance.jumlahItem > 0,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
          selectedIcon: const Icon(Icons.shopping_cart),
          label: 'Keranjang',
        ),
        const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Pesanan'),
        const NavigationDestination(
            icon: Icon(Icons.history), label: 'Riwayat'),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  final MenuAnggota menuAktif;
  final void Function(MenuAnggota) onPilih;
  const _Sidebar({required this.menuAktif, required this.onPilih});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.asset(AppVariant.logoAsset,
                      height: 28,
                      errorBuilder: (context, error, stack) => const Icon(
                          Icons.storefront,
                          size: 28,
                          color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppVariant.namaPendek,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: _daftarMenu
                  .where((m) =>
                      (m.menu != MenuAnggota.isiSaldo ||
                          Sesi.instance.aktifkanTopup) &&
                      (m.menu != MenuAnggota.bayarQr ||
                          Sesi.instance.aktifkanBayarQr))
                  .map((m) => _BarisMenu(
                        item: m,
                        aktif: m.menu == menuAktif,
                        onTap: () => onPilih(m.menu),
                      ))
                  .toList(),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text(
              Sesi.instance.kode.isEmpty
                  ? Sesi.instance.nama
                  : '${Sesi.instance.nama}\n${Sesi.instance.kode}',
              style:
                  const TextStyle(color: AppColors.sidebarText, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarisMenu extends StatelessWidget {
  final _ItemMenu item;
  final bool aktif;
  final VoidCallback onTap;
  const _BarisMenu(
      {required this.item, required this.aktif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Jumlah isi keranjang ditempel di menu Keranjang supaya anggota tahu
    // ada barang tertahan tanpa harus membuka halamannya.
    final jumlah =
        item.menu == MenuAnggota.keranjang ? Keranjang.instance.jumlahItem : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: aktif ? AppColors.sidebarBgActive : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.ikon,
                    size: 18,
                    color: aktif
                        ? AppColors.sidebarTextActive
                        : AppColors.sidebarText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: aktif
                          ? AppColors.sidebarTextActive
                          : AppColors.sidebarText,
                      fontWeight: aktif ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (jumlah > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$jumlah',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Topbar extends StatelessWidget {
  final List<Widget> aksi;
  const _Topbar({required this.aksi});

  @override
  Widget build(BuildContext context) {
    final sesi = Sesi.instance;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (sesi.tampilkanSaldo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('${sesi.labelSaldo}: ${rupiah(sesi.saldo)}',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5)),
                ],
              ),
            ),
          if (sesi.tampilkanCashback) ...[
            const SizedBox(width: 8),
            Text('${sesi.labelCashback}: ${rupiah(sesi.sisaCashback)}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
          const Spacer(),
          ...aksi,
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              sesi.nama.isEmpty
                  ? '?'
                  : sesi.nama.characters.first.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(sesi.nama,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }
}
