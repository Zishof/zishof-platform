import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/apotik_breakpoints.dart';
import '../../core/apotik_design_tokens.dart';
import 'apotik_status_pill.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Kartu obat untuk katalog POS (§10).</h3>
///
/// Memperbaiki temuan audit: katalog lama hanya satu baris teks
/// `kode • stok • harga`, sehingga kasir sulit membedakan obat secara cepat.
///
/// **Hanya merender field yang BENAR-BENAR dikirim server** pada
/// `apotik_item_cari`: `nama, kode, kandungan, barcode, satuan, stok,
/// hargaJual, lasa, terkendali` dan — sejak IR-01 diimplementasikan di
/// backend — `golonganObat, bentukSediaan, kekuatan, highAlert, coldChain`.
/// Field yang tidak dikirim tetap TIDAK dikarang: badge hanya muncul bila
/// nilainya benar-benar ada, sehingga server lama pun aman.
class MedicationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  /// Ditampilkan saat item tidak bisa dijual dari layar ini (mis. baris
  /// racikan pada resep). Alasan WAJIB diisi supaya pengguna tahu sebabnya.
  final String? alasanTerkunci;

  /// Aksi kecil di sudut kartu (mis. tombol riwayat AuditTrails). Opsional
  /// supaya katalog kasir tetap bersih; hanya layar master yang mengisinya.
  final Widget? aksiTambahan;

  const MedicationCard({
    super.key,
    required this.item,
    this.onTap,
    this.alasanTerkunci,
    this.aksiTambahan,
  });

  double get _stok => (item['stok'] as num?)?.toDouble() ?? 0;
  double get _harga => (item['hargaJual'] as num?)?.toDouble() ?? 0;
  bool get _lasa => item['lasa'] == true;
  bool get _terkendali => item['terkendali'] == true;
  bool get _highAlert => item['highAlert'] == true;
  bool get _coldChain => item['coldChain'] == true;
  String get _golongan => '${item['golonganObat'] ?? ''}';

  /// "500 mg • tablet" — hanya bagian yang ada yang ikut dirender.
  String get _sediaan => [
        '${item['kekuatan'] ?? ''}'.trim(),
        '${item['bentukSediaan'] ?? ''}'.trim(),
      ].where((e) => e.isNotEmpty).join(' • ');
  bool get _terkunci => alasanTerkunci != null;

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    final habis = _stok <= 0;
    final nonaktif = _terkunci || habis;

    // Urutan badge = urutan risiko: high-alert & terkendali lebih dulu supaya
    // terbaca sebelum kasir sempat menekan kartunya.
    final golonganPill = ApotikStatusPill.golongan(_golongan);
    final badge = <Widget>[
      if (_highAlert) ApotikStatusPill.highAlert(),
      if (_terkendali) ApotikStatusPill.terkendali(),
      if (golonganPill != null && !_terkendali) golonganPill,
      if (_lasa) ApotikStatusPill.lasa(),
      if (_coldChain) ApotikStatusPill.coldChain(),
      if (habis) ApotikStatusPill.stokHabis(),
    ];

    return ApotikResponsive(
      builder: (context, layout) {
        return Opacity(
          opacity: nonaktif ? 0.62 : 1,
          child: Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusCard),
            child: InkWell(
              // Item terkunci/habis tidak bisa ditap — pagar keselamatan
              // ditegakkan sebelum sampai ke keranjang.
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
                          : t.border),
                ),
                child: Column(
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
                              // LASA ditebalkan: pembeda tambahan selain badge,
                              // sesuai aturan "jangan andalkan warna saja".
                              fontWeight:
                                  _lasa ? FontWeight.w800 : FontWeight.w600,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        if (_harga > 0) ...[
                          const SizedBox(width: 8),
                          Text(_rp.format(_harga),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: t.primary)),
                        ],
                        if (aksiTambahan != null) aksiTambahan!,
                      ],
                    ),
                    if (_sediaan.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_sediaan,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.textSecondary)),
                    ],
                    if ('${item['kandungan'] ?? ''}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('${item['kandungan']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: t.textSecondary,
                              fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      [
                        '${item['kode'] ?? ''}',
                        'stok ${_stok.toStringAsFixed(_stok % 1 == 0 ? 0 : 2)} ${item['satuan'] ?? ''}'
                            .trim(),
                        if ('${item['barcode'] ?? ''}'.trim().isNotEmpty)
                          'barcode ${item['barcode']}',
                      ].where((e) => e.trim().isNotEmpty).join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: t.textSecondary),
                    ),
                    if (badge.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: badge),
                    ],
                    if (alasanTerkunci != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.lock_outline, size: 13, color: t.warning),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(alasanTerkunci!,
                              style:
                                  TextStyle(fontSize: 11.5, color: t.warning)),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
