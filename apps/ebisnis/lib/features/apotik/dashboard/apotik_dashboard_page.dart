import 'package:flutter/material.dart';

import '../../../sesi.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_context_bar.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';
import 'apotik_dashboard_data.dart';
import 'apotik_priority_card.dart';

/// <h3>Dashboard Operasional Apotik — "command center" (Fase 2, mockup 01).</h3>
///
/// Menjawab pertanyaan kedua pengguna: *apa pekerjaan paling penting yang
/// harus saya selesaikan sekarang?* Menggantikan dashboard lama yang hanya
/// berisi kartu statistik + chip menu dengan ruang kerja berisi prioritas
/// nyata: antrean resep, batch mendekati kedaluwarsa, dan stok habis.
///
/// **Semua angka berasal dari aksi server yang benar-benar ada.** Metrik
/// mockup yang belum didukung backend (cold-chain, tugas shift, transaksi
/// pending, SLA) sengaja TIDAK dibuatkan kartu — lihat IR-02/IR-06/IR-10.
class ApotikDashboardPage extends StatefulWidget {
  /// Disuntik pada test agar tidak menyentuh jaringan.
  final ApotikDashboardLoader? loader;

  /// Dipanggil saat kartu/tugas diketuk; pemanggil yang tahu cara bernavigasi
  /// (dashboard tidak mengimpor layar lain agar tidak menciptakan siklus).
  final void Function(ApotikTujuanDashboard tujuan)? onBuka;

  const ApotikDashboardPage({super.key, this.loader, this.onBuka});

  @override
  State<ApotikDashboardPage> createState() => _ApotikDashboardPageState();
}

enum ApotikTujuanDashboard { resep, batch, stok, kasir }

class _ApotikDashboardPageState extends State<ApotikDashboardPage> {
  late final ApotikDashboardLoader _loader =
      widget.loader ?? ApotikDashboardLoader();
  bool _memuat = true;
  ApotikRingkasan _ringkasan = const ApotikRingkasan();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    final hasil = await _loader.muat();
    setStateIfMounted(() {
      _ringkasan = hasil;
      _memuat = false;
    });
  }

  void _buka(ApotikTujuanDashboard tujuan) => widget.onBuka?.call(tujuan);

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return Scaffold(
      backgroundColor: t.surfaceMuted,
      body: ApotikResponsive(
        builder: (context, layout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _contextBar(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: EdgeInsets.only(
                        bottom: ApotikBreakpoints.paddingHalaman(layout)),
                    children: [
                      ApotikPageHeader(
                        judul: 'Dashboard Operasional',
                        subjudul: _subjudul(),
                        aksi: [
                          IconButton(
                            onPressed: _memuat ? null : _muat,
                            tooltip: 'Muat ulang',
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      if (_memuat)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: ApotikLoadingState(
                              pesan: 'Memuat prioritas apotek…'),
                        )
                      else ...[
                        _kartuPrioritas(layout),
                        _daftarTugas(layout),
                        _galatSumber(layout),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _subjudul() {
    final waktu = _ringkasan.diperbaruiPada;
    if (waktu == null) return 'Prioritas kerja apotek hari ini';
    final jam = '${waktu.hour.toString().padLeft(2, '0')}:'
        '${waktu.minute.toString().padLeft(2, '0')}';
    return 'Prioritas kerja apotek • data per $jam';
  }

  Widget _contextBar() {
    final s = Sesi.instance;
    return ApotikContextBar(
      ruas: [
        // Nilai diambil dari sesi aktif — bukan teks contoh. Ini yang menutup
        // temuan audit "identitas Kantin Demo membingungkan di modul apotik".
        ApotikKonteksRuas(
            ikon: Icons.local_pharmacy_outlined,
            label: 'Apotek',
            nilai: s.tokoNama),
        ApotikKonteksRuas(
            ikon: Icons.person_outline, label: 'Pengguna', nilai: s.userId),
        ApotikKonteksRuas(
            ikon: Icons.badge_outlined,
            label: 'Peran',
            nilai:
                s.isAdmin ? 'Admin' : (s.actorType.isEmpty ? '' : s.actorType)),
      ],
    );
  }

  Widget _kartuPrioritas(ApotikLayout layout) {
    final r = _ringkasan;
    final kartu = <Widget>[
      ApotikPriorityCard(
        ikon: Icons.description_outlined,
        judul: 'Resep menunggu',
        angka: r.resepMenunggu,
        angkaLabel: r.label(r.resepMenunggu),
        satuan: 'resep',
        makna: 'Belum ditebus — telaah dan siapkan obatnya',
        catatan: r.galat['resep'],
        tujuanLabel: 'Buka antrean resep',
        nada: ApotikPriorityNada.klinis,
        onTap: Sesi.instance.bolehMenuVarianBaru('apotik_resep')
            ? () => _buka(ApotikTujuanDashboard.resep)
            : null,
      ),
      ApotikPriorityCard(
        ikon: Icons.event_busy_outlined,
        judul: 'Batch mendekati kedaluwarsa',
        angka: r.batchNearExpiry,
        angkaLabel: r.label(r.batchNearExpiry),
        satuan: 'batch',
        makna:
            '≤ ${ApotikDashboardLoader.ambangNearExpiryHari} hari — keluarkan lebih dulu (FEFO)',
        catatan: r.galat['batch'],
        tujuanLabel: 'Buka batch & expiry',
        nada: ApotikPriorityNada.perhatian,
        onTap: Sesi.instance.bolehMenuVarianBaru('apotik_batch')
            ? () => _buka(ApotikTujuanDashboard.batch)
            : null,
      ),
      ApotikPriorityCard(
        ikon: Icons.production_quantity_limits_outlined,
        judul: 'Stok habis',
        angka: r.stokHabis,
        angkaLabel: r.label(r.stokHabis),
        satuan: 'obat',
        makna: 'Tidak dapat dijual — perlu pengadaan',
        catatan: r.galat['item'],
        tujuanLabel: 'Buka persediaan',
        nada: ApotikPriorityNada.mendesak,
        onTap: Sesi.instance.bolehMenuVarianBaru('apotik_formularium')
            ? () => _buka(ApotikTujuanDashboard.stok)
            : null,
      ),
      ApotikPriorityCard(
        ikon: Icons.medication_outlined,
        judul: 'Obat terbaca',
        angka: r.obatTerbaca,
        angkaLabel: r.label(r.obatTerbaca),
        satuan: 'item',
        makna: 'Katalog yang terbaca pada halaman pertama',
        catatan: r.galat['item'],
        tujuanLabel: 'Buka kasir',
        onTap: Sesi.instance.bolehMenuVarianBaru('apotik_kasir')
            ? () => _buka(ApotikTujuanDashboard.kasir)
            : null,
      ),
    ];

    final kolom = switch (layout) {
      ApotikLayout.compactMobile => 1,
      ApotikLayout.tablet => 2,
      ApotikLayout.desktopCompact => 2,
      ApotikLayout.desktopStandard => 4,
      ApotikLayout.desktopWide => 4,
    };
    final padding = ApotikBreakpoints.paddingHalaman(layout);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: LayoutBuilder(builder: (context, c) {
        const jarak = ApotikDesignTokens.gridSpacing;
        final lebar = (c.maxWidth - jarak * (kolom - 1)) / kolom;
        return Wrap(
          spacing: jarak,
          runSpacing: jarak,
          children: [
            for (final k in kartu) SizedBox(width: lebar, child: k),
          ],
        );
      }),
    );
  }

  Widget _daftarTugas(ApotikLayout layout) {
    final t = ApotikDesignTokens.of(context);
    final padding = ApotikBreakpoints.paddingHalaman(layout);
    final tugas = _ringkasan.tugas;
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 20, padding, 0),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(children: [
                Icon(Icons.task_alt, size: 17, color: t.primary),
                const SizedBox(width: 8),
                Text('Perlu tindakan',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary)),
                const Spacer(),
                if (tugas.isNotEmpty)
                  Text('${tugas.length} item',
                      style: TextStyle(fontSize: 12, color: t.textSecondary)),
              ]),
            ),
            Divider(height: 1, color: t.border),
            if (tugas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: ApotikEmptyState(
                  ikon: Icons.verified_outlined,
                  judul: 'Tidak ada pekerjaan mendesak',
                  petunjuk:
                      'Antrean resep, batch mendekati kedaluwarsa, dan stok '
                      'habis semuanya bersih saat data ini diambil.',
                ),
              )
            else
              for (var i = 0; i < tugas.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.border),
                _barisTugas(tugas[i]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _barisTugas(ApotikTugas tugas) {
    final t = ApotikDesignTokens.of(context);
    final (ikon, pill, tujuan) = switch (tugas.jenis) {
      ApotikTugasJenis.resep => (
          Icons.description_outlined,
          const ApotikStatusPill(
              teks: 'Resep',
              nada: ApotikStatusNada.klinis,
              ikon: Icons.description_outlined,
              penjelasan: 'Menunggu ditebus'),
          ApotikTujuanDashboard.resep,
        ),
      ApotikTugasJenis.expiry => (
          Icons.event_busy_outlined,
          tugas.urutan < 0
              ? ApotikStatusPill.kedaluwarsa()
              : ApotikStatusPill.nearExpiry(tugas.urutan),
          ApotikTujuanDashboard.batch,
        ),
      ApotikTugasJenis.stok => (
          Icons.production_quantity_limits_outlined,
          ApotikStatusPill.stokHabis(),
          ApotikTujuanDashboard.stok,
        ),
    };
    return ListTile(
      dense: true,
      minVerticalPadding: 10,
      leading: Icon(ikon, size: 18, color: t.textSecondary),
      title: Text(tugas.judul,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: t.textPrimary)),
      subtitle: Text(tugas.keterangan,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
      trailing: pill,
      onTap: () => _buka(tujuan),
    );
  }

  /// Galat per sumber ditampilkan TERPISAH dari kartu supaya kegagalan satu
  /// endpoint tidak menyembunyikan data endpoint lain yang berhasil.
  Widget _galatSumber(ApotikLayout layout) {
    if (_ringkasan.galat.isEmpty) return const SizedBox.shrink();
    final t = ApotikDesignTokens.of(context);
    final padding = ApotikBreakpoints.paddingHalaman(layout);
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
          border: Border.all(color: t.danger.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.error_outline, size: 16, color: t.danger),
              const SizedBox(width: 6),
              Text('Sebagian data tidak dapat dimuat',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.dangerText)),
            ]),
            const SizedBox(height: 6),
            for (final e in _ringkasan.galat.entries)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• ${e.key}: ${e.value}',
                    style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}
