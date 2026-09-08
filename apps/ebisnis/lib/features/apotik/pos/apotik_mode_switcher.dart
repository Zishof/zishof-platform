import 'package:flutter/material.dart';

import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import 'apotik_pos_state.dart';

/// <h3>Pemilih mode transaksi (OTC / Resep / Racikan / Produksi).</h3>
///
/// Keempat mode memiliki alur server end-to-end dan dapat dipilih langsung.
class ApotikModeSwitcher extends StatelessWidget {
  final ApotikModePos aktif;
  final ValueChanged<ApotikModePos> onPilih;
  final List<ApotikModePos> modes;

  /// Untuk command bar sempit, semua mode tetap satu baris dan dapat digeser;
  /// tidak ada mode yang hilang atau turun jauh dari area pencarian.
  final bool gulirHorizontal;

  const ApotikModeSwitcher({
    super.key,
    required this.aktif,
    required this.onPilih,
    this.modes = ApotikModePos.values,
    this.gulirHorizontal = false,
  });

  IconData _ikon(ApotikModePos m) => switch (m) {
        ApotikModePos.otc => Icons.shopping_bag_outlined,
        ApotikModePos.resep => Icons.description_outlined,
        ApotikModePos.racikan => Icons.science_outlined,
        ApotikModePos.produksi => Icons.factory_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return ApotikResponsive(
      builder: (context, layout) {
        final pilihan = <Widget>[
          for (final m in modes) _chip(context, t, m, layout),
        ];
        if (gulirHorizontal) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < pilihan.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  pilihan[i],
                ],
              ],
            ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pilihan,
        );
      },
    );
  }

  Widget _chip(BuildContext context, ApotikDesignTokens t, ApotikModePos m,
      ApotikLayout layout) {
    final terpilih = m == aktif;
    final warna = terpilih ? t.primary : t.textSecondary;

    final isi = Container(
      constraints: BoxConstraints(
          maxWidth: 240,
          minHeight:
              layout.isMobile ? ApotikBreakpoints.targetSentuhMinimum : 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: terpilih ? t.primarySoft : t.surface,
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(
          color: terpilih ? t.primary : t.border,
          width: terpilih ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_ikon(m), size: 16, color: warna),
          const SizedBox(width: 6),
          // Flexible + ellipsis: chip dipakai juga di panel konteks selebar
          // 260 px, sehingga label panjang ("OTC / Obat Bebas") harus boleh
          // memendek alih-alih meluber keluar kartu.
          Flexible(
            child: Text(m.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: terpilih ? FontWeight.w700 : FontWeight.w500,
                    color: warna)),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: terpilih,
      label: m.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
          onTap: () => onPilih(m),
          child: isi,
        ),
      ),
    );
  }
}
