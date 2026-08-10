import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'anggota/tab_data_member.dart';
import 'anggota/tab_jenis_member.dart';
import 'anggota/tab_notifikasi.dart';
import 'anggota/tab_sinkronisasi.dart';
import 'anggota/tab_tipe_member.dart';
import 'anggota/tab_topup.dart';

/// Layar "Pelanggan" (padanan `anggota.jsp` JSP -- "Manajemen Anggota") --
/// 6 sub-tab persis urutan JSP: Data Member Baru, Jenis Member, Tipe
/// Member, Topup, Notifikasi, Sinkronisasi Siswa/Mahasiswa. Setiap tab
/// StatefulWidget terpisah (lihat folder anggota/, pola sama dgn
/// RingkasanScreen 9-tab) -- memuat datanya sendiri di initState, lazy
/// sesuai TabBarView.
///
/// TIDAK diporting dari JSP (di luar cakupan permintaan "6 tab" ini):
/// penampil password member (dekripsi plaintext -- pola tak aman) dan
/// tombol kirim-notifikasi per-baris/massal dari tab Data Member (fitur
/// terpisah, JSP-only utk saat ini).
class AnggotaScreen extends StatefulWidget {
  const AnggotaScreen({super.key});

  @override
  State<AnggotaScreen> createState() => _AnggotaScreenState();
}

class _AnggotaScreenState extends State<AnggotaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.anggota,
      judul: 'Pelanggan',
      subjudul: 'Kelola data member/pelanggan toko Anda',
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
              Tab(text: 'Data Member Baru'),
              Tab(text: 'Jenis Member'),
              Tab(text: 'Tipe Member'),
              Tab(text: 'Topup'),
              Tab(text: 'Notifikasi'),
              Tab(text: 'Sinkronisasi Siswa/Mahasiswa'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              AnggotaTabDataMember(),
              AnggotaTabJenisMember(),
              AnggotaTabTipeMember(),
              AnggotaTabTopup(),
              AnggotaTabNotifikasi(),
              AnggotaTabSinkronisasi(),
            ]),
          ),
        ],
      ),
    );
  }
}
