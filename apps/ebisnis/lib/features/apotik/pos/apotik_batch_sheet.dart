import 'package:flutter/material.dart';

import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import '../shared/widgets/apotik_status_pill.dart';

/// <h3>Pemilih batch FEFO (§10 FefoBatchPicker).</h3>
///
/// Dipindahkan dari `kasir_apotik_screen._SheetPilihBatch` — logika prefill
/// FEFO dan validasi sisa dipertahankan PERSIS agar pagar keselamatan yang
/// sudah terbukti tidak berubah. Tambahan pada versi ini:
///
/// - **IR-02**: lot berstatus karantina/recall/rusak/ditahan ikut terkunci
///   (bukan hanya kedaluwarsa) dan alasannya diambil dari server, bukan
///   dikarang klien. Prefill FEFO melewati lot yang tidak layak.
/// - Status memakai ikon+teks+warna, bukan warna saja.
///
/// Mengembalikan `List<Map>` berisi `{kadaluarsa_id, qty, tanggal}` — bentuk
/// yang sama dengan yang dikirim ke `apotik_bayar`.
class ApotikBatchSheet extends StatefulWidget {
  final String namaItem;
  final List<Map<String, dynamic>> batches;
  final double qtyDiminta;

  const ApotikBatchSheet({
    super.key,
    required this.namaItem,
    required this.batches,
    required this.qtyDiminta,
  });

  /// true bila batch tidak boleh dipakai sama sekali (kedaluwarsa ATAU status
  /// lot tidak layak). Server tetap menegakkan aturan yang sama.
  static bool terkunci(Map<String, dynamic> b) =>
      b['kedaluwarsa'] == true || b['lotLayak'] == false;

  /// Alasan terkunci yang bisa dibaca kasir; null bila batch layak.
  static String? alasanTerkunci(Map<String, dynamic> b) {
    if (b['kedaluwarsa'] == true) return 'Kedaluwarsa — tidak boleh dijual';
    if (b['lotLayak'] == false) {
      final alasan = '${b['alasanLot'] ?? ''}'.trim();
      return alasan.isEmpty ? 'Lot ditahan — tidak dapat dipilih' : alasan;
    }
    return null;
  }

  @override
  State<ApotikBatchSheet> createState() => _ApotikBatchSheetState();
}

class _ApotikBatchSheetState extends State<ApotikBatchSheet> {
  late final Map<int, TextEditingController> _qty;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _qty = {};
    // Prefill FEFO: penuhi qty diminta dari batch paling dekat kedaluwarsa
    // dulu, MELEWATI batch yang terkunci (kedaluwarsa / lot tidak layak).
    var sisaMinta = widget.qtyDiminta;
    for (var i = 0; i < widget.batches.length; i++) {
      final b = widget.batches[i];
      final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
      double ambil = 0;
      if (!ApotikBatchSheet.terkunci(b) && sisaMinta > 0 && sisa > 0) {
        ambil = sisaMinta < sisa ? sisaMinta : sisa;
        sisaMinta -= ambil;
      }
      _qty[i] = TextEditingController(
          text: ambil <= 0 ? '' : ambil.toStringAsFixed(0));
    }
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _pakai() {
    final pilihan = <Map<String, dynamic>>[];
    for (var i = 0; i < widget.batches.length; i++) {
      final b = widget.batches[i];
      if (ApotikBatchSheet.terkunci(b)) continue;
      final q = double.tryParse(_qty[i]!.text.trim()) ?? 0;
      if (q <= 0) continue;
      final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
      if (q > sisa) {
        setState(() => _galat =
            'Qty batch ED ${b['tanggalKadaluarsa']} melebihi sisa ($sisa).');
        return;
      }
      pilihan.add({
        'kadaluarsa_id': b['kadaluarsaId'],
        'qty': q,
        'tanggal': b['tanggalKadaluarsa'],
      });
    }
    if (pilihan.isEmpty) {
      setState(() => _galat = 'Pilih minimal satu batch (qty > 0).');
      return;
    }
    Navigator.pop(context, pilihan);
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      expand: false,
      builder: (context, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pilih Batch — ${widget.namaItem}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: t.textPrimary)),
          const SizedBox(height: 4),
          Text(
              'Urutan FEFO (terdekat kedaluwarsa didahulukan). Batch kedaluwarsa '
              'atau lot yang ditahan terkunci dan tidak dapat dipilih.',
              style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.batches.length; i++)
            _kartuBatch(t, i, widget.batches[i]),
          if (_galat != null) ...[
            const SizedBox(height: 4),
            Text(_galat!, style: TextStyle(fontSize: 12, color: t.danger)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: ApotikBreakpoints.targetSentuhMinimum,
            child: FilledButton.icon(
              onPressed: _pakai,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Pakai Batch Ini'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuBatch(ApotikDesignTokens t, int i, Map<String, dynamic> b) {
    final kunci = ApotikBatchSheet.terkunci(b);
    final alasan = ApotikBatchSheet.alasanTerkunci(b);
    final sisa = ((b['sisa'] as num?) ?? 0).toDouble();
    final habis = sisa <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kunci ? t.danger.withValues(alpha: 0.06) : t.surface,
        border: Border.all(color: kunci ? t.danger : t.border),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ED: ${b['tanggalKadaluarsa'] ?? '-'}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: kunci ? t.danger : t.textPrimary)),
              Text('Sisa: ${sisa.toStringAsFixed(sisa % 1 == 0 ? 0 : 2)}',
                  style: TextStyle(fontSize: 11.5, color: t.textSecondary)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (b['kedaluwarsa'] == true)
                  ApotikStatusPill.kedaluwarsa()
                else if (b['lotLayak'] == false)
                  ApotikStatusPill.lotDitahan(alasan ?? 'Lot ditahan')
                else if (habis)
                  ApotikStatusPill.stokHabis()
                else
                  ApotikStatusPill.layak(),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: TextField(
            controller: _qty[i],
            enabled: !kunci && !habis,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Qty', border: OutlineInputBorder(), isDense: true),
          ),
        ),
      ]),
    );
  }
}
