import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import 'anggota/tab_data_member.dart';
import 'anggota/tab_jenis_member.dart';
import 'anggota/tab_notifikasi.dart';
import 'anggota/tab_sinkronisasi.dart';
import 'anggota/tab_tipe_member.dart';
import 'anggota/tab_topup.dart';
import 'anggota/tab_saldo_voucher.dart';
import 'anggota/tab_mutasi_tabungan.dart';
import 'anggota/tab_mutasi_hutang.dart';
import 'anggota/tab_pembantu_piutang.dart';
import 'anggota/tab_pengajuan_limit.dart';
import 'anggota/tab_satuan_kerja.dart';

/// Layar "Pelanggan" (padanan `anggota.jsp` JSP -- "Manajemen Anggota") --
/// 6 sub-tab persis urutan JSP: Data Member Baru, Jenis Member, Tipe
/// Member, Topup, Notifikasi, Sinkronisasi Sivitas. Setiap tab
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
  int _versiDataMember = 0;

  @override
  void initState() {
    super.initState();
    // WAJIB sama dgn jumlah Tab di TabBar dan widget di TabBarView; kalau
    // berbeda, layar ini gagal dibuka. Sebelumnya tertinggal di 9 padahal
    // tabnya sudah bertambah.
    _tab = TabController(length: 12, vsync: this);
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
      actionsAppBar: const [
        IndikatorSinkronMaster(),
      ],
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
              Tab(text: 'Pengajuan Melebihi Limit'),
              Tab(text: 'Topup'),
              Tab(text: 'Saldo Voucher'),
              Tab(text: 'Mutasi Voucher'),
              Tab(text: 'Mutasi Hutang'),
              Tab(text: 'Pembantu Piutang'),
              Tab(text: 'Notifikasi'),
              Tab(text: 'Satuan Kerja'),
              Tab(text: 'Sinkronisasi Sivitas'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: [
              AnggotaTabDataMember(
                refreshVersion: _versiDataMember,
                onBukaSinkronisasi: () => _tab.animateTo(11),
              ),
              const AnggotaTabJenisMember(),
              const AnggotaTabTipeMember(),
              const AnggotaTabPengajuanLimit(),
              const AnggotaTabTopup(),
              const AnggotaTabSaldoVoucher(),
              const AnggotaTabMutasiTabungan(),
              const AnggotaTabMutasiHutang(),
              const AnggotaTabPembantuPiutang(),
              const AnggotaTabNotifikasi(),
              const AnggotaTabSatuanKerja(),
              AnggotaTabSinkronisasi(
                onSinkronSelesai: () => setState(() => _versiDataMember++),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
