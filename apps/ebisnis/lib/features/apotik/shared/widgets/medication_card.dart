import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/apotik_breakpoints.dart';
import '../../core/apotik_design_tokens.dart';
import 'apotik_status_pill.dart';
import 'medication_image.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Kartu obat bersama untuk katalog POS dan formularium.
///
/// Hanya field yang benar-benar dikirim server yang dirender. Dukungan foto
/// bersifat opsional/non-breaking; respons lama mendapat fallback kategori.
class MedicationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  final String? alasanTerkunci;
  final Widget? aksiTambahan;

  /// Aksi utama eksplisit di sisi kanan. POS mengisinya dengan tombol tambah;
  /// layar master boleh tetap mengandalkan tap seluruh kartu.
  final String? labelAksiUtama;
  final IconData ikonAksiUtama;

  const MedicationCard({
    super.key,
    required this.item,
    this.onTap,
    this.alasanTerkunci,
    this.aksiTambahan,
    this.labelAksiUtama,
    this.ikonAksiUtama = Icons.add,
  });

  double get _stok => (item['stok'] as num?)?.toDouble() ?? 0;
  double get _harga => (item['hargaJual'] as num?)?.toDouble() ?? 0;
  bool get _lasa => item['lasa'] == true;
  bool get _terkendali => item['terkendali'] == true;
  bool get _highAlert => item['highAlert'] == true;
  bool get _coldChain => item['coldChain'] == true;
  String get _golongan => '${item['golonganObat'] ?? ''}';
  bool get _terkunci => alasanTerkunci != null;

  String get _sediaan => [
        '${item['kekuatan'] ?? ''}'.trim(),
        '${item['bentukSediaan'] ?? ''}'.trim(),
      ].where((e) => e.isNotEmpty).join(' • ');

  List<ApotikStatusPill> _badge(bool habis) {
    final golonganPill = ApotikStatusPill.golongan(_golongan);
    final adaRisiko = _highAlert ||
        _terkendali ||
        golonganPill != null ||
        _lasa ||
        _coldChain;
    return <ApotikStatusPill>[
      if (_highAlert) ApotikStatusPill.highAlert(),
      if (_terkendali) ApotikStatusPill.terkendali(),
      if (golonganPill != null && !_terkendali) golonganPill,
      if (_lasa) ApotikStatusPill.lasa(),
      if (_coldChain) ApotikStatusPill.coldChain(),
      if (habis)
        ApotikStatusPill.stokHabis()
      else if (_stok <= 10)
        const ApotikStatusPill(
          teks: 'Stok menipis',
          nada: ApotikStatusNada.peringatan,
          ikon: Icons.inventory_2_outlined,
          penjelasan: 'Periksa kebutuhan pengadaan',
          rapat: true,
        )
      else if (!adaRisiko)
        const ApotikStatusPill(
          teks: 'Stok aman',
          nada: ApotikStatusNada.sukses,
          ikon: Icons.check_circle,
          rapat: true,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final habis = _stok <= 0;
    final nonaktif = _terkunci || habis;
    final badge = _badge(habis);

    return ApotikResponsive(
      builder: (context, layout) {
        final skala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        final teksBesar = skala > 1.15;
        return Opacity(
          opacity: nonaktif ? 0.62 : 1,
          child: Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
            child: InkWell(
              onTap: nonaktif ? null : onTap,
              borderRadius:
                  BorderRadius.circular(ApotikDesignTokens.radiusCard),
              child: Container(
                constraints: const BoxConstraints(
                    minHeight: ApotikBreakpoints.targetSentuhMinimum),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(ApotikDesignTokens.radiusCard),
                  border: Border.all(
                    color: (_terkendali || _highAlert)
                        ? t.danger.withValues(alpha: 0.45)
                        : t.border,
                  ),
                ),
                child: teksBesar
                    ? _isiTeksBesar(t, badge, nonaktif)
                    : badge.length > 2
                        ? _isiRisikoPadat(t, badge, nonaktif)
                        : _isiNormal(t, layout, badge, nonaktif),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Banyak badge keselamatan membutuhkan ruang horizontal. Thumbnail tetap
  /// dikorbankan lebih dulu; identitas tekstual dan badge tidak pernah
  /// dipotong hanya demi mempertahankan dekorasi gambar.
  Widget _isiRisikoPadat(
      ApotikDesignTokens t, List<ApotikStatusPill> badge, bool nonaktif) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _informasi(t, badge)),
        if (labelAksiUtama != null) ...[
          const SizedBox(width: 8),
          _aksiUtama(nonaktif, lebarPenuh: false),
        ],
      ],
    );
  }

  Widget _isiNormal(ApotikDesignTokens t, ApotikLayout layout,
      List<ApotikStatusPill> badge, bool nonaktif) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MedicationImage(
          item: item,
          width: layout.isMobile ? 66 : 72,
          height: layout.isMobile ? 82 : 88,
        ),
        const SizedBox(width: 10),
        Expanded(child: _informasi(t, badge)),
        if (labelAksiUtama != null) ...[
          const SizedBox(width: 8),
          _aksiUtama(nonaktif, lebarPenuh: false),
        ],
      ],
    );
  }

  /// Pada skala teks aksesibilitas, thumbnail dikeluarkan dan tombol memakai
  /// lebar penuh agar informasi keselamatan tidak terpotong.
  Widget _isiTeksBesar(
      ApotikDesignTokens t, List<ApotikStatusPill> badge, bool nonaktif) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _informasi(t, badge),
        if (labelAksiUtama != null) ...[
          const SizedBox(height: 10),
          _aksiUtama(nonaktif, lebarPenuh: true),
        ],
      ],
    );
  }

  Widget _informasi(ApotikDesignTokens t, List<ApotikStatusPill> badge) {
    final kandungan = '${item['kandungan'] ?? ''}'.trim();
    final produsen =
        '${item['produsen'] ?? item['pabrik'] ?? item['manufacturer'] ?? ''}'
            .trim();
    final barcode = '${item['barcode'] ?? ''}'.trim();
    final metadata = Text(
      [
        'stok ${_stok.toStringAsFixed(_stok % 1 == 0 ? 0 : 2)} ${item['satuan'] ?? ''}'
            .trim(),
        '${item['kode'] ?? ''}',
      ].where((e) => e.trim().isNotEmpty).join('  •  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, color: t.textSecondary),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${item['nama'] ?? '-'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: _lasa ? FontWeight.w800 : FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
            if (aksiTambahan != null) aksiTambahan!,
          ],
        ),
        if (_sediaan.isNotEmpty ||
            produsen.isNotEmpty ||
            kandungan.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            [
              if (produsen.isNotEmpty) produsen,
              if (_sediaan.isNotEmpty)
                _sediaan
              else if (kandungan.isNotEmpty)
                kandungan,
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: t.textSecondary),
          ),
        ],
        if (_harga > 0) ...[
          const SizedBox(height: 4),
          Text(
            _rp.format(_harga),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.primary,
            ),
          ),
        ],
        const SizedBox(height: 4),
        if (barcode.isEmpty)
          metadata
        else
          Tooltip(message: 'Barcode $barcode', child: metadata),
        if (badge.isNotEmpty) ...[
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final b in badge)
                ApotikStatusPill(
                  teks: b.teks,
                  nada: b.nada,
                  penjelasan: b.penjelasan,
                  ikon: b.ikon,
                  rapat: true,
                ),
            ],
          ),
        ],
        if (alasanTerkunci != null) ...[
          const SizedBox(height: 7),
          Row(children: [
            Icon(Icons.lock_outline, size: 13, color: t.warning),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                alasanTerkunci!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: t.warningText),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _aksiUtama(bool nonaktif, {required bool lebarPenuh}) {
    final label = '$labelAksiUtama ${item['nama'] ?? ''}';
    final tombol = FilledButton(
      onPressed: nonaktif ? null : onTap,
      style: FilledButton.styleFrom(
        padding: lebarPenuh
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
            : EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: lebarPenuh
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ikonAksiUtama, size: 20),
                const SizedBox(width: 8),
                Flexible(child: Text(labelAksiUtama!)),
              ],
            )
          : Icon(ikonAksiUtama, size: 20),
    );
    return Semantics(
      button: true,
      enabled: !nonaktif,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: lebarPenuh ? double.infinity : 44,
          height: lebarPenuh ? null : 44,
          child: tombol,
        ),
      ),
    );
  }
}
