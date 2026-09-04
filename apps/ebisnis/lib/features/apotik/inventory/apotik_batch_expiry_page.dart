import 'package:flutter/material.dart';

import '../../../services/master_offline.dart';
import '../../../widgets/kilau_perubahan.dart';
import '../../../widgets/proses_simpan_master.dart';
import '../../../widgets/riwayat_data_dialog.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../core/apotik_lokal_dulu.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';

/// <h3>Batch, Expiry &amp; FEFO (Fase 5, mockup 05).</h3>
///
/// Memakai `apotik_batch_monitor` (ambang hari dapat diubah) dan menampilkan
/// setiap lot beserta **status IR-02**. Aksi ubah status (karantina, recall,
/// rusak, ditahan, kembali layak) memanggil `apotik_batch_status_ubah` yang
/// **mewajibkan alasan** saat menahan lot — server yang menegakkannya, layar
/// ini hanya menyediakan tempat mengisinya.
class ApotikBatchExpiryPage extends StatefulWidget {
  final MuatDaftarApotik? muatDaftar;
  final SimpanMasterApotik? simpan;

  const ApotikBatchExpiryPage({super.key, this.muatDaftar, this.simpan});

  @override
  State<ApotikBatchExpiryPage> createState() => _ApotikBatchExpiryPageState();
}

class _ApotikBatchExpiryPageState extends State<ApotikBatchExpiryPage> {
  late final MuatDaftarApotik _muatDaftar =
      widget.muatDaftar ?? MasterOffline.daftarCacheDulu;
  late final SimpanMasterApotik _simpan = widget.simpan ?? prosesSimpanMaster;

  static const _pilihanHari = <int>[30, 60, 90, 180, 365];
  int _hari = 365;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _batch = [];

  /// Diff emisi server -> animasi kilau baris + bilah pemberitahuan.
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Baca LOKAL DULU: monitor kedaluwarsa harus tetap terbaca saat jaringan
      // mati -- justru saat itulah petugas perlu tahu lot mana yang tidak
      // boleh dijual.
      await _muatDaftar(
        'apotik_batch_monitor',
        {'hari_ke_depan': _hari, 'page_size': 100},
        kunciCacheBatchApotik,
        onData: (hasil) {
          if (!mounted) return;
          final dariServer = hasil['dariServer'] == true;
          final data = ((hasil['data'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          // Paling mendesak di atas: yang sudah/paling dekat kedaluwarsa.
          data.sort((a, b) => '${a['tanggalKadaluarsa'] ?? ''}'
              .compareTo('${b['tanggalKadaluarsa'] ?? ''}'));
          setStateIfMounted(() {
            _batch = data;
            _idBaru = dariServer
                ? Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{})
                : {};
            _idBerubah = dariServer
                ? Set<String>.from(
                    hasil['idBerubah'] as Set? ?? const <String>{})
                : {};
            _jumlahHapus = dariServer ? (hasil['jumlahHapus'] as int? ?? 0) : 0;
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        if (_batch.isEmpty) _galat = '$e';
        _memuat = false;
      });
    }
  }

  /// Bilah "pembaruan dari server": lot yang berubah karena petugas lain
  /// (mis. dikarantina dari terminal sebelah) harus terlihat, bukan diam-diam
  /// tertukar di layar.
  Widget _bilahPerubahan(ApotikDesignTokens t) {
    final bagian = <String>[
      if (_idBaru.isNotEmpty) '${_idBaru.length} baru',
      if (_idBerubah.isNotEmpty) '${_idBerubah.length} berubah',
      if (_jumlahHapus > 0) '$_jumlahHapus hilang',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(color: t.info.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.cloud_download_outlined, size: 15, color: t.info),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Pembaruan dari server: ${bagian.join(', ')}.',
              style: TextStyle(fontSize: 11.5, color: t.textPrimary)),
        ),
      ]),
    );
  }

  int? _sisaHari(String? tanggal) {
    if (tanggal == null || tanggal.trim().isEmpty) return null;
    final t = DateTime.tryParse(tanggal.trim());
    if (t == null) return null;
    final kini = DateTime.now();
    return DateTime(t.year, t.month, t.day)
        .difference(DateTime(kini.year, kini.month, kini.day))
        .inDays;
  }

  Future<void> _ubahStatus(Map<String, dynamic> b) async {
    final statusSekarang = '${b['statusLot'] ?? 'ELIGIBLE'}';
    var dipilih = statusSekarang;
    final alasan = TextEditingController();
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c2, setD) {
        final menahan = dipilih != 'ELIGIBLE';
        return AlertDialog(
          title: Text('Status lot — ${b['nama'] ?? b['kode'] ?? ''}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: dipilih,
              decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(
                    value: 'ELIGIBLE', child: Text('Layak dijual')),
                DropdownMenuItem(
                    value: 'HELD', child: Text('Ditahan sementara')),
                DropdownMenuItem(value: 'QUARANTINE', child: Text('Karantina')),
                DropdownMenuItem(
                    value: 'RECALL', child: Text('Ditarik (recall)')),
                DropdownMenuItem(value: 'DAMAGED', child: Text('Rusak')),
              ],
              onChanged: (v) => setD(() => dipilih = v ?? 'ELIGIBLE'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: alasan,
              maxLines: 2,
              decoration: InputDecoration(
                labelText:
                    menahan ? 'Alasan menahan lot *' : 'Alasan (opsional)',
                helperText: menahan
                    ? 'Wajib, minimal 5 karakter — penahanan stok harus dapat '
                        'ditelusuri.'
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c2, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c2, true),
                child: const Text('Simpan')),
          ],
        );
      }),
    );
    if (lanjut != true || !mounted) return;
    try {
      // Diantre bila jaringan mati: penahanan lot yang tercatat terlambat
      // masih jauh lebih baik daripada penahanan yang hilang sama sekali.
      // Server tetap yang menegakkan "alasan wajib" saat kiriman sampai.
      final r = await _simpan(
        context,
        aksi: 'apotik_batch_status_ubah',
        body: {
          'kadaluarsa_id': b['kadaluarsaId'],
          'status': dipilih,
          'alasan': alasan.text.trim(),
        },
        kunci: 'apotik_batch_status:${b['kadaluarsaId']}',
        cacheKey: kunciCacheBatchApotik,
        rowLokal: {
          ...b,
          'statusLot': dipilih,
          'lotLayak': dipilih == 'ELIGIBLE',
        },
      );
      if (!mounted) return;
      if (r['offline'] != true) _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal mengubah status: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return ApotikResponsive(builder: (context, layout) {
      return Scaffold(
        backgroundColor: t.surfaceMuted,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ApotikPageHeader(
            judul: 'Batch, Expiry & FEFO',
            subjudul: 'Lot yang mendekati kedaluwarsa dan status penahanannya',
            aksi: [
              IconButton(
                  onPressed: _memuat ? null : _muat,
                  tooltip: 'Muat ulang',
                  icon: const Icon(Icons.refresh)),
            ],
          ),
          if (_idBaru.isNotEmpty || _idBerubah.isNotEmpty || _jumlahHapus > 0)
            _bilahPerubahan(t),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ApotikBreakpoints.paddingHalaman(layout)),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final h in _pilihanHari)
                ChoiceChip(
                  label: Text('$h hari'),
                  selected: _hari == h,
                  onSelected: (_) {
                    setStateIfMounted(() => _hari = h);
                    _muat();
                  },
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _memuat
                ? const ApotikLoadingState(pesan: 'Memuat monitor batch…')
                : _galat != null
                    ? ApotikErrorState(pesan: _galat!, onCobaLagi: _muat)
                    : _batch.isEmpty
                        ? ApotikEmptyState(
                            ikon: Icons.verified_outlined,
                            judul: 'Tidak ada batch mendekati kedaluwarsa',
                            petunjuk:
                                'Dalam $_hari hari ke depan tidak ada lot yang '
                                'perlu diprioritaskan keluar.')
                        : ListView.builder(
                            padding: EdgeInsets.symmetric(
                                horizontal:
                                    ApotikBreakpoints.paddingHalaman(layout),
                                vertical: 4),
                            itemCount: _batch.length,
                            itemBuilder: (context, i) => KilauBaris(
                              kunci: MasterOffline.kunciBaris(
                                  _batch[i], 'kadaluarsaId'),
                              idBaru: _idBaru,
                              idBerubah: _idBerubah,
                              child: _kartu(t, _batch[i], layout),
                            ),
                          ),
          ),
        ]),
      );
    });
  }

  Widget _kartu(
      ApotikDesignTokens t, Map<String, dynamic> b, ApotikLayout layout) {
    final hari = _sisaHari('${b['tanggalKadaluarsa'] ?? ''}');
    final kedaluwarsa = b['kedaluwarsa'] == true || (hari != null && hari < 0);
    final layak = b['lotLayak'] != false;
    final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
        border:
            Border.all(color: (kedaluwarsa || !layak) ? t.danger : t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${b['nama'] ?? b['kode'] ?? '-'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary)),
          ),
          Text('sisa ${sisa.toStringAsFixed(sisa % 1 == 0 ? 0 : 2)}',
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ]),
        const SizedBox(height: 2),
        Text('ED ${b['tanggalKadaluarsa'] ?? '-'} • ${b['kode'] ?? ''}',
            style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              if (kedaluwarsa)
                ApotikStatusPill.kedaluwarsa()
              else if (hari != null)
                ApotikStatusPill.nearExpiry(hari),
              if (!layak)
                ApotikStatusPill.lotDitahan(
                    '${b['alasanLot'] ?? 'Lot ditahan'}'),
              if (layak && !kedaluwarsa && sisa > 0) ApotikStatusPill.layak(),
            ]),
          ),
          TextButton.icon(
            onPressed: () => _ubahStatus(b),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Ubah status'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Riwayat data ini (AuditTrails)',
            icon: const Icon(Icons.history, size: 16),
            onPressed: () => tampilkanRiwayatData(
              context,
              entitas: 'apotik_batch',
              id: b['kadaluarsaId'] ?? b['id'] ?? 0,
              judul: '${b['nama'] ?? b['kode'] ?? ''}',
            ),
          ),
        ]),
      ]),
    );
  }
}
