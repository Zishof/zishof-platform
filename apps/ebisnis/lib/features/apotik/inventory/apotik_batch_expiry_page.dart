import 'package:flutter/material.dart';

import '../../../api_client.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_page_header.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';

typedef PanggilBatch = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// <h3>Batch, Expiry &amp; FEFO (Fase 5, mockup 05).</h3>
///
/// Memakai `apotik_batch_monitor` (ambang hari dapat diubah) dan menampilkan
/// setiap lot beserta **status IR-02**. Aksi ubah status (karantina, recall,
/// rusak, ditahan, kembali layak) memanggil `apotik_batch_status_ubah` yang
/// **mewajibkan alasan** saat menahan lot — server yang menegakkannya, layar
/// ini hanya menyediakan tempat mengisinya.
class ApotikBatchExpiryPage extends StatefulWidget {
  final PanggilBatch? panggil;
  const ApotikBatchExpiryPage({super.key, this.panggil});

  @override
  State<ApotikBatchExpiryPage> createState() => _ApotikBatchExpiryPageState();
}

class _ApotikBatchExpiryPageState extends State<ApotikBatchExpiryPage> {
  late final PanggilBatch _panggil =
      widget.panggil ?? (aksi, body) => ApiClient.instance.aksi(aksi, body);

  static const _pilihanHari = <int>[30, 60, 90, 180];
  int _hari = 90;
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _batch = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final r = await _panggil(
          'apotik_batch_monitor', {'hari_ke_depan': _hari, 'page_size': 100});
      if (!_sukses(r)) {
        setStateIfMounted(() {
          _galat = '${r['description'] ?? 'Gagal memuat monitor batch.'}';
          _memuat = false;
        });
        return;
      }
      final data = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // Paling mendesak di atas: yang sudah/paling dekat kedaluwarsa.
      data.sort((a, b) => '${a['tanggalKadaluarsa'] ?? ''}'
          .compareTo('${b['tanggalKadaluarsa'] ?? ''}'));
      setStateIfMounted(() {
        _batch = data;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
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
      final r = await _panggil('apotik_batch_status_ubah', {
        'kadaluarsa_id': b['kadaluarsaId'],
        'status': dipilih,
        'alasan': alasan.text.trim(),
      });
      if (!mounted) return;
      // Pesan server apa adanya, termasuk penolakan "alasan wajib".
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${r['description'] ?? (_sukses(r) ? 'Status lot diubah.' : r['status'])}'),
        backgroundColor:
            _sukses(r) ? null : Theme.of(context).colorScheme.error,
      ));
      if (_sukses(r)) _muat();
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
                            itemBuilder: (context, i) =>
                                _kartu(t, _batch[i], layout),
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
        ]),
      ]),
    );
  }
}
