import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../product_profile.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/safe_state.dart';
import 'kasir_apotik_screen.dart';
import 'persediaan_apotik_screen.dart';
import '../../app_variant.dart';
import '../../features/apotik/dashboard/apotik_dashboard_page.dart';
import '../../features/apotik/inventory/apotik_batch_expiry_page.dart';
import '../../features/apotik/inventory/apotik_formularium_page.dart';
import '../../features/apotik/prescription/apotik_resep_page.dart';
import 'laporan_apotik_screen.dart';
import 'pos_help.dart';

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
  bool _provisionBerjalan = false;
  String? _error;
  int _obatTerbaca = 0;
  int _stokTersedia = 0;
  int _batchKritis = 0;

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
      try {
        final obat = await ApiClient.instance
            .aksi('apotik_item_cari', {'page_size': 100});
        final data = obat['data'];
        if (data is List) {
          _obatTerbaca = data.length;
          _stokTersedia = data.where((e) {
            return e is Map && ((e['stok'] as num?)?.toDouble() ?? 0) > 0;
          }).length;
        }
        final batch = await ApiClient.instance.aksi(
            'apotik_batch_monitor', {'hari_ke_depan': 90, 'page_size': 100});
        final daftarBatch = batch['data'];
        _batchKritis = daftarBatch is List ? daftarBatch.length : 0;
      } catch (_) {
        // Konfigurasi/akses menu tetap dapat ditampilkan ketika server lama
        // belum menyediakan endpoint ringkasan farmasi.
      }
      setStateIfMounted(() => _memuat = false);
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _isiDataContoh() async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Isi data contoh Apotik?'),
        content: const Text(
            'Server akan menyiapkan katalog obat, racikan, tenaga medis, akun demo, dan stok contoh secara idempoten. Fitur ini hanya berjalan bila konfigurasi data_sample_ebisnis aktif.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Mulai di Latar')),
        ],
      ),
    );
    if (setuju != true) return;
    setStateIfMounted(() => _provisionBerjalan = true);
    try {
      await ApiClient.instance.aksi('apotik_provision_demo', {
        'konfirmasi': 'SEED-DEMO-APOTIK',
        'background': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Data contoh sedang dibuat di latar. Katalog besar dapat memerlukan beberapa menit.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      setStateIfMounted(() => _provisionBerjalan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Sesi.instance;
    // MODERNISASI FASE 2: varian APOTIK memakai dashboard command center
    // berbasis prioritas (ApotikDashboardPage). Varian eMedik -- yang berbagi
    // layar ini -- SENGAJA tetap memakai tampilan kartu+chip lama supaya
    // perubahan apotik tidak merembet ke varian lain (aturan multi-varian).
    if (AppVariant.isApotik) return _dashboardModern();
    final adaMenuApotik = _menuApotik.any((m) => s.bolehMenuVarianBaru(m.$1)) ||
        _menuEmedik.any((m) => s.bolehMenuVarianBaru(m.$1));
    return AppShell(
      menuAktif: MenuEBisnis.berandaApotik,
      judul: 'Dashboard Apotik',
      subjudul: 'Kasir, resep, persediaan, batch, dan analitik farmasi',
      scrollable: false,
      actionsAppBar: [
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang',
            onPressed: _muat),
      ],
      aksiHeader: Wrap(spacing: 8, children: [
        if (s.isAdmin)
          OutlinedButton.icon(
            onPressed: _provisionBerjalan ? null : _isiDataContoh,
            icon: _provisionBerjalan
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Isi Data Contoh'),
          ),
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang',
            onPressed: _muat),
      ]),
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
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
                    children: [
                      _kartuRingkasan(context),
                      const SizedBox(height: 16),
                      if (!adaMenuApotik)
                        AppInfoBanner(
                          icon: Icons.lock_outline,
                          color: AppColors.warning,
                          text:
                              'Akun ini belum diberi menu POS Apotik/eMedik oleh admin '
                              '(Grup Pengguna). Menu apotek fail-closed: kunci yang belum '
                              'diaktifkan tidak pernah terbuka sendiri.',
                        ),
                      _grupMenu(context, 'Operasional Apotik', _menuApotik),
                      if (AppProductProfile.aktif.isEmedik) ...[
                        const SizedBox(height: 12),
                        _grupMenu(context, 'Layanan Medis', _menuEmedik),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _kartuRingkasan(BuildContext context) {
    final s = Sesi.instance;
    return LayoutBuilder(builder: (context, box) {
      final lebar = box.maxWidth;
      final kolom = lebar >= 1100
          ? 4
          : lebar >= 620
              ? 2
              : 1;
      final cardWidth = (lebar - ((kolom - 1) * 12)) / kolom;
      final cards = <Widget>[
        _statCard(context, Icons.medication_outlined, 'Obat terdata',
            _obatTerbaca == 100 ? '100+' : '$_obatTerbaca', AppColors.info),
        _statCard(context, Icons.inventory_2_outlined, 'Obat tersedia',
            '$_stokTersedia', AppColors.success),
        _statCard(context, Icons.event_busy_outlined, 'Batch ≤ 90 hari',
            '$_batchKritis', AppColors.warning),
        _statCard(
            context,
            Icons.storefront_outlined,
            'Apotek aktif',
            s.tokoNama.isEmpty ? 'Belum dipilih' : s.tokoNama,
            const Color(0xFF7C3AED)),
      ];
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final card in cards) SizedBox(width: cardWidth, child: card)
        ],
      );
    });
  }

  Widget _statCard(BuildContext context, IconData icon, String label,
      String nilai, Color warna) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warna.withValues(alpha: .18)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: AppColors.latarLembut(warna),
              borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: warna),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nilai,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context))),
              ]),
        ),
      ]),
    );
  }

  /// Tujuan navigasi menu yang layarnya SUDAH dibangun -- bertambah per fase.
  /// Menu tanpa tujuan tetap chip status (hak akses tetap terverifikasi UAT).
  /// Command center Fase 2 dibungkus AppShell existing supaya sidebar, menu
  /// aktif, dan bantuan kontekstual tetap konsisten dengan layar lain.
  Widget _dashboardModern() {
    return AppShell(
      menuAktif: MenuEBisnis.berandaApotik,
      judul: 'Dashboard Apotik',
      subjudul: 'Prioritas kerja apotek: resep, expiry, dan stok',
      scrollable: false,
      body: ApotikDashboardPage(onBuka: _bukaTujuanDashboard),
    );
  }

  void _bukaTujuanDashboard(ApotikTujuanDashboard tujuan) {
    final layar = switch (tujuan) {
      // FASE 4: antrean resep kini punya layarnya sendiri (sebelumnya
      // dialihkan ke kasir karena layar ini belum ada).
      ApotikTujuanDashboard.resep => const _HalamanAntreanResep(),
      // FASE 5: ruang kerja batch/expiry sendiri (sebelumnya tab persediaan).
      ApotikTujuanDashboard.batch => const _HalamanBatchExpiry(),
      // FASE 5: formularium punya layar sendiri (editor profil obat IR-01).
      ApotikTujuanDashboard.stok => const _HalamanFormularium(),
      ApotikTujuanDashboard.kasir => _layarTujuan('apotik_kasir'),
    };
    if (layar == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => layar));
  }

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
      case 'apotik_laporan':
        return const LaporanApotikScreen();
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
                      fontSize: 12, fontWeight: FontWeight.w600, color: warna)),
              const SizedBox(width: 6),
              Icon(
                  tujuan != null
                      ? Icons.chevron_right
                      : (boleh ? Icons.check_circle : Icons.block),
                  size: 13,
                  color: warna),
            ]),
          );
          return Row(mainAxisSize: MainAxisSize.min, children: [
            tujuan == null
                ? chip
                : InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => tujuan)),
                    child: chip,
                  ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Bantuan ${m.$2}',
              icon: const Icon(Icons.help_outline, size: 19),
              onPressed: () => PosHelp.open(context, m.$1),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}

/// Pembungkus AppShell untuk antrean resep supaya sidebar & menu aktif
/// konsisten dengan layar apotik lainnya.
class _HalamanAntreanResep extends StatelessWidget {
  const _HalamanAntreanResep();

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      menuAktif: MenuEBisnis.kasirApotik,
      judul: 'Antrean Resep',
      subjudul:
          'Telaah, daftar periksa pra-serah, pemeriksaan kedua, konseling',
      scrollable: false,
      body: ApotikResepPage(),
    );
  }
}

/// Pembungkus AppShell untuk ruang kerja Batch, Expiry & FEFO.
class _HalamanBatchExpiry extends StatelessWidget {
  const _HalamanBatchExpiry();

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      menuAktif: MenuEBisnis.persediaanApotik,
      judul: 'Batch, Expiry & FEFO',
      subjudul: 'Monitor lot mendekati kedaluwarsa dan status penahanan',
      scrollable: false,
      body: ApotikBatchExpiryPage(),
    );
  }
}

/// Pembungkus AppShell untuk Formularium / Master Obat.
class _HalamanFormularium extends StatelessWidget {
  const _HalamanFormularium();

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      menuAktif: MenuEBisnis.persediaanApotik,
      judul: 'Formularium / Master Obat',
      subjudul:
          'Golongan, bentuk sediaan, kekuatan, LASA, high-alert, cold-chain',
      scrollable: false,
      body: ApotikFormulariumPage(),
    );
  }
}
