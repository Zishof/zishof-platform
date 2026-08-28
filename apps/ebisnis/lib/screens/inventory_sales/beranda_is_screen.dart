import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/master_offline.dart';
import '../../product_profile.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

/// Label tampilan kunci menu varian Inventory & Sales (kunci server =
/// `EbisnisMenuKatalog.MODUL_INVENTORY_SALES`, lihat AIS). Dipakai kartu
/// "Modul Anda" menampilkan izin NYATA yang diberikan role aktor -- sumber
/// datanya `Sesi.menuInventorySales` (fail-closed, kunci hilang = nonaktif).
const _labelModulIs = <String, String>{
  'master_supplier': 'Master Supplier',
  'master_customer': 'Master Customer',
  'master_sales': 'Master Sales',
  'persediaan': 'Persediaan & Kartu Stok',
  'harga': 'Master & Analisis Harga',
  'hutang': 'Hutang Supplier (AP)',
  'penjualan_sales': 'Penjualan Sales',
  'piutang': 'Piutang Customer (AR)',
  'surat_perintah_sales': 'Surat Perintah Sales Jalan',
  'nota_sales': 'Nota Sales (Sesi)',
  'biaya_sales': 'Biaya Sales',
  'pembelian_sales': 'Pembelian dalam Sesi',
  'rekonsiliasi_sales': 'Rekonsiliasi Sesi',
  'kas_jurnal': 'Kas & Jurnal',
  'laba_rugi': 'Laba / Rugi',
  'laporan_inventory_sales': 'Laporan Inventory & Sales',
};

/// <h3>Beranda varian "eBisnis Inventory & Sales" -- landing per aktor (P1).</h3>
///
/// - Admin / Pemilik Sales-Inventory: ringkasan konteks (toko, role, izin modul
///   NYATA dari server) -- modul 48-layar dibuka lewat sidebar begitu layarnya
///   tersedia per fase (P2 dst.); yang belum tersedia TIDAK ditampilkan sebagai
///   tombol semu (prinsip paritas: tanpa "Segera Hadir" palsu).
/// - Sales Keliling: "Sesi Hari Ini" -- membaca `currentTripId` dari
///   `si_actor_context`; belum ada SPJ = empty-state jujur + tombol muat ulang
///   (BUKAN akses admin).
///
/// Layar ini juga MEMUAT `konfigurasi` sendiri (lewat [Sesi.terapkanKonfig])
/// karena pada varian ini KasirScreen belum tentu pernah dibuka -- kasir POS
/// existing tidak berubah alurnya.
class BerandaInventorySalesScreen extends StatefulWidget {
  const BerandaInventorySalesScreen({super.key});

  @override
  State<BerandaInventorySalesScreen> createState() =>
      _BerandaInventorySalesScreenState();
}

class _BerandaInventorySalesScreenState
    extends State<BerandaInventorySalesScreen> with JejakGalat {
  bool _memuat = true;
  String? _error;

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
      final konfig = await MasterOffline.objekDenganCache(
          'konfigurasi', const {}, 'konfigurasi');
      Sesi.instance.terapkanKonfig(konfig);
      // Konteks aktor terbaru (currentTripId dsb.) -- aksi khusus varian; bila
      // server belum di-deploy dgn dukungan si_, konfigurasi saja sudah cukup.
      try {
        final aktor = await ApiClient.instance.aksi('si_actor_context');
        final data = aktor['aktor'];
        if (data is Map<String, dynamic>) {
          Sesi.instance.currentTripId = data['currentTripId'] is num
              ? (data['currentTripId'] as num).toInt()
              : null;
        }
      } catch (_) {
        // Server lama / akses ditolak -- biarkan nilai dari konfigurasi.
      }
      setStateIfMounted(() => _memuat = false);
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = terapkanGalat(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.berandaInventorySales,
      judul: 'Beranda ${AppProductProfile.aktif.namaSidebar}',
      subjudul: AppProductProfile.aktif.deskripsiAktor(),
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muat)
      ],
      aksiHeader: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Muat Ulang',
          onPressed: _muat),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        AppDetailGalatOpsional(detail: detailUntuk(_error)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _muat, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _kartuKonteks(context),
                      const SizedBox(height: 12),
                      if (Sesi.instance.isSalesKeliling)
                        _kartuSesiHariIni(context)
                      else
                        _kartuModul(context),
                    ],
                  ),
                ),
    );
  }

  Widget _kartuKonteks(BuildContext context) {
    final sesi = Sesi.instance;
    return AppSectionCard(
      judul: 'Konteks Akun',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppDetailChip(
                  icon: Icons.badge_outlined,
                  label: AppProductProfile.aktif.deskripsiAktor()),
              AppDetailChip(
                  icon: Icons.person_outline,
                  label: sesi.userId.isEmpty ? '-' : sesi.userId),
              AppDetailChip(
                  icon: Icons.store_mall_directory_outlined,
                  label: sesi.tokoNama.isEmpty
                      ? (sesi.isAdmin ? 'Semua toko (global)' : 'Tanpa toko')
                      : sesi.tokoNama),
              if (sesi.activeRoleId.isNotEmpty)
                AppDetailChip(
                    icon: Icons.verified_user_outlined,
                    label: 'Role: ${sesi.activeRoleId}'),
              if (sesi.isSalesKeliling && sesi.salesKode.isNotEmpty)
                AppDetailChip(
                    icon: Icons.qr_code_2_outlined,
                    label: 'Kode Sales: ${sesi.salesKode}'),
            ],
          ),
          if (sesi.actorType.isEmpty) ...[
            const SizedBox(height: 10),
            const AppInfoBanner(
              icon: Icons.cloud_off_outlined,
              text:
                  'Server belum mengirim konteks aktor Inventory & Sales (versi server lama). '
                  'Perbarui server AIS lalu Muat Ulang.',
              color: AppColors.warning,
            ),
          ],
        ],
      ),
    );
  }

  /// Sales Keliling: status sesi hari ini -- `currentTripId` null = belum ada
  /// SPJ ditugaskan (fase SPJ/Nota Sales menyusul P5; sampai server punya SPJ
  /// utk sales ini, empty-state inilah kebenarannya).
  Widget _kartuSesiHariIni(BuildContext context) {
    final tripId = Sesi.instance.currentTripId;
    return AppSectionCard(
      judul: 'Sesi Hari Ini',
      child: tripId != null
          ? Row(
              children: [
                const Icon(Icons.route_outlined,
                    size: 32, color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Sesi perjalanan #$tripId sedang berjalan.',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_available_outlined,
                        size: 32, color: AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                          'Belum ada Surat Perintah Sales Jalan yang ditugaskan '
                          'kepada Anda hari ini.',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _muat,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Periksa Tugas Terbaru'),
                ),
              ],
            ),
    );
  }

  /// Admin/Pemilik: izin modul NYATA dari server (bukan daftar statis) --
  /// modul aktif tampil sbg chip; navigasinya lewat sidebar begitu layar
  /// per-fase tersedia. Admin melihat semua (bypass server-side).
  Widget _kartuModul(BuildContext context) {
    final aktif = <String>[];
    final nonaktif = <String>[];
    for (final k in _labelModulIs.keys) {
      (Sesi.instance.bolehMenuIs(k) ? aktif : nonaktif).add(k);
    }
    return AppSectionCard(
      judul: 'Modul Inventory & Sales Anda',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            aktif.isEmpty
                ? 'Role Anda belum diberi akses modul Inventory & Sales. Hubungi admin '
                    '(menu Hak Akses) untuk mengaktifkannya.'
                : 'Izin modul di bawah ini dibaca langsung dari pengaturan Grup Pengguna '
                    'di server (fail-closed). Layar tiap modul dibuka bertahap per fase '
                    'implementasi 48 layar.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in aktif)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.success),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 15, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(_labelModulIs[k] ?? k,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
