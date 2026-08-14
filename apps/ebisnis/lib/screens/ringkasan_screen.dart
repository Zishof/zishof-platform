import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'ringkasan/tab_umum.dart';
import 'ringkasan/tab_keuangan.dart';
import 'ringkasan/tab_produk.dart';
import 'ringkasan/tab_pelanggan.dart';
import 'ringkasan/tab_peringkat.dart';
import 'ringkasan/tab_resep.dart';
import 'ringkasan/tab_ramalan.dart';
import 'ringkasan/tab_promo.dart';
import 'ringkasan/tab_kepatuhan.dart';
import 'ringkasan/tab_sesi_kas.dart';

/// Layar Ringkasan (padanan ringkasan.html/ringkasan-renderer.js Electron) --
/// 9 sub-tab dasbor lintas-modul. Setiap tab adalah StatefulWidget terpisah
/// (lihat folder ringkasan/) yg memuat datanya sendiri di initState -- karena
/// TabBarView (PageView di baliknya) hanya membangun tab yg benar-benar
/// terlihat/berdekatan, ini otomatis meniru perilaku "lazy-load saat tab
/// pertama dibuka" versi Electron tanpa perlu koordinasi eksplisit.
class RingkasanScreen extends StatefulWidget {
  const RingkasanScreen({super.key});

  @override
  State<RingkasanScreen> createState() => _RingkasanScreenState();
}

class _RingkasanScreenState extends State<RingkasanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 10, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.ringkasan,
      judul: 'Dashboard Bisnis',
      subjudul: 'Ringkasan performa bisnis Anda secara real-time',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Ringkasan Umum'),
              Tab(text: 'Keuangan & Kinerja'),
              Tab(text: 'Produk & Inventaris'),
              Tab(text: 'Perilaku Pelanggan'),
              Tab(text: 'Peringkat Mitra'),
              Tab(text: 'Resep, HPP & Margin'),
              Tab(text: 'Ramalan Penjualan'),
              Tab(text: 'Promo & Cashback'),
              Tab(text: 'Kepatuhan Operasional'),
              Tab(text: 'Riwayat Sesi Kas'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              RingkasanTabUmum(),
              RingkasanTabKeuangan(),
              RingkasanTabProduk(),
              RingkasanTabPelanggan(),
              RingkasanTabPeringkat(),
              RingkasanTabResep(),
              RingkasanTabRamalan(),
              RingkasanTabPromo(),
              RingkasanTabKepatuhan(),
              RingkasanTabSesiKas(),
            ]),
          ),
        ],
      ),
    );
  }
}
