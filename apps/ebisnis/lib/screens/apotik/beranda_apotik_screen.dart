import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import '../login_screen.dart';
import 'kasir_apotik_screen.dart';
import 'persediaan_apotik_screen.dart';

/// <h3>Beranda varian "POS Apotik" -- landing setelah login (LANGKAH 2).</h3>
///
/// Layar KONTEKS nyata, bukan mockup: memuat ulang aksi `konfigurasi` lalu
/// menampilkan identitas kasir/toko/role + status tiap menu apotik dari
/// `aksesMenu` server (fail-closed lewat [Sesi.bolehMenuVarianBaru] -- kunci
/// hilang = TIDAK boleh, kebalikan `bolehMenu` lama). Menu yang nyala di sini
/// belum bisa dibuka -- layar kasir/persediaan apotik dibangun FASE A/B
/// (lihat perintah awal LANGKAH 3); status ditampilkan sebagai chip agar
/// pemetaan hak akses bisa diverifikasi UAT SEBELUM layar-layarnya ada.
class BerandaApotikScreen extends StatefulWidget {
  const BerandaApotikScreen({super.key});

  @override
  State<BerandaApotikScreen> createState() => _BerandaApotikScreenState();
}

class _BerandaApotikScreenState extends State<BerandaApotikScreen> {
  bool _memuat = true;
  String? _error;

  static const _menuApotik = <(String, String, IconData)>[
    ('apotik_kasir', 'Kasir Apotik', Icons.point_of_sale),
    ('apotik_resep', 'Tebus Resep Dokter', Icons.description_outlined),
    ('apotik_racikan', 'Racikan', Icons.science_outlined),
    ('apotik_formularium', 'Formularium & Obat', Icons.medication_outlined),
    ('apotik_batch', 'Batch & Kedaluwarsa', Icons.event_busy_outlined),
    ('apotik_pengadaan', 'Pengadaan / PBF', Icons.local_shipping_outlined),
    ('apotik_stok_opname', 'Stok Opname Apotik', Icons.fact_check_outlined),
    ('apotik_retur', 'Retur Obat', Icons.assignment_return_outlined),
    ('apotik_narkotika', 'Obat Terkendali', Icons.gpp_maybe_outlined),
    ('apotik_laporan', 'Laporan Apotik', Icons.bar_chart_outlined),
  ];

  static const _menuEmedik = <(String, String, IconData)>[
    ('emedik_kasir', 'Kasir Layanan Medis', Icons.medical_services_outlined),
    ('emedik_pendaftaran', 'Pendaftaran Pasien', Icons.how_to_reg_outlined),
    ('emedik_tagihan', 'Tagihan Kunjungan', Icons.receipt_long_outlined),
    ('emedik_deposit', 'Deposit Pasien', Icons.savings_outlined),
    ('emedik_penjamin', 'Penjamin & Asuransi', Icons.verified_user_outlined),
    ('emedik_laporan', 'Laporan Kasir Medis', Icons.summarize_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final konfig = await ApiClient.instance.aksi('konfigurasi');
      Sesi.instance.terapkanKonfig(konfig);
      setStateIfMounted(() => _memuat = false);
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _keluar() async {
    try {
      await ApiClient.instance.aksi('logout');
    } catch (_) {
      // Token sisi server kedaluwarsa sendiri -- logout lokal tetap jalan.
    }
    await ApiClient.instance.hapusToken();
    Sesi.instance.reset();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final s = Sesi.instance;
    final adaMenuApotik =
        _menuApotik.any((m) => s.bolehMenuVarianBaru(m.$1)) ||
            _menuEmedik.any((m) => s.bolehMenuVarianBaru(m.$1));
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: const Text('POS Apotik'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Muat Ulang',
              onPressed: _muat),
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Keluar',
              onPressed: _keluar),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _muat, child: const Text('Coba Lagi')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      AppSectionCard(
                        judul: 'Konteks Sesi',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _baris(context, 'Pengguna', s.userId),
                            _baris(context, 'Toko / Apotek',
                                s.tokoNama.isEmpty ? '-' : s.tokoNama),
                            _baris(
                                context,
                                'Peran',
                                s.isAdmin
                                    ? 'Admin (akses penuh)'
                                    : (s.activeRoleId.isEmpty
                                        ? '-'
                                        : s.activeRoleId)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!adaMenuApotik)
                        AppInfoBanner(
                          icon: Icons.lock_outline,
                          color: AppColors.warning,
                          text:
                              'Akun ini belum diberi menu POS Apotik/eMedik oleh admin '
                              '(Grup Pengguna). Menu apotek fail-closed: kunci yang belum '
                              'diaktifkan tidak pernah terbuka sendiri.',
                        ),
                      _grupMenu(context, 'Menu Apotik (eFarmasi)', _menuApotik),
                      const SizedBox(height: 12),
                      _grupMenu(
                          context, 'Menu Layanan Medis (eMedik)', _menuEmedik),
                      const SizedBox(height: 12),
                      AppInfoBanner(
                        icon: Icons.construction_outlined,
                        color: AppColors.info,
                        text:
                            'Layar kasir apotik (tebus resep, batch/kedaluwarsa, obat '
                            'terkendali, LASA) dibangun FASE A -- chip di atas menunjukkan '
                            'HAK AKSES nyata dari server untuk verifikasi lebih awal.',
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _baris(BuildContext context, String label, String nilai) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context)))),
          Expanded(
              child: Text(nilai.isEmpty ? '-' : nilai,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  /// Tujuan navigasi menu yang layarnya SUDAH dibangun -- bertambah per fase.
  /// Menu tanpa tujuan tetap chip status (hak akses tetap terverifikasi UAT).
  Widget? _layarTujuan(String kunci) {
    switch (kunci) {
      case 'apotik_kasir':
        return const KasirApotikScreen();
      case 'apotik_formularium':
        return const PersediaanApotikScreen(tabAwal: 0);
      case 'apotik_batch':
        return const PersediaanApotikScreen(tabAwal: 1);
      case 'apotik_pengadaan':
        return const PersediaanApotikScreen(tabAwal: 2);
      case 'apotik_stok_opname':
        return const PersediaanApotikScreen(tabAwal: 3);
      case 'apotik_retur':
        return const PersediaanApotikScreen(tabAwal: 4);
    }
    return null;
  }

  Widget _grupMenu(BuildContext context, String judul,
      List<(String, String, IconData)> daftar) {
    return AppSectionCard(
      judul: judul,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: daftar.map((m) {
          final boleh = Sesi.instance.bolehMenuVarianBaru(m.$1);
          final tujuan = boleh ? _layarTujuan(m.$1) : null;
          final warna = boleh ? AppColors.success : AppColors.danger;
          final chip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(warna),
              border: Border.all(color: warna.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.$3, size: 15, color: warna),
              const SizedBox(width: 6),
              Text(m.$2,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: warna)),
              const SizedBox(width: 6),
              Icon(
                  tujuan != null
                      ? Icons.chevron_right
                      : (boleh ? Icons.check_circle : Icons.block),
                  size: 13,
                  color: warna),
            ]),
          );
          if (tujuan == null) return chip;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => tujuan)),
            child: chip,
          );
        }).toList(),
      ),
    );
  }
}
