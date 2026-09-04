import 'package:flutter/material.dart';

import '../core/apotik_breakpoints.dart';
import '../core/apotik_design_tokens.dart';
import 'apotik_pos_state.dart';

/// <h3>Pemilih mode transaksi (OTC / Resep / Racikan / Produksi).</h3>
///
/// Menutup temuan audit "mode OTC, Resep Dokter, Racikan, dan Produksi perlu
/// tampil lebih eksplisit". Mode yang belum didukung server tetap DITAMPILKAN
/// tetapi dinonaktifkan beserta alasannya — lebih jujur daripada
/// menyembunyikannya (pengguna tahu fitur itu direncanakan) dan lebih aman
/// daripada tombol yang tidak menulis apa pun.
class ApotikModeSwitcher extends StatelessWidget {
  final ApotikModePos aktif;
  final ValueChanged<ApotikModePos> onPilih;

  const ApotikModeSwitcher({
    super.key,
    required this.aktif,
    required this.onPilih,
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
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in ApotikModePos.values) _chip(context, t, m, layout),
          ],
        );
      },
    );
  }

  Widget _chip(BuildContext context, ApotikDesignTokens t, ApotikModePos m,
      ApotikLayout layout) {
    final terpilih = m == aktif;
    final aktifkan = m.didukungServer;
    final warna =
        !aktifkan ? t.textSecondary : (terpilih ? t.primary : t.textSecondary);

    final isi = Container(
      constraints: BoxConstraints(
          maxWidth: 240,
          minHeight:
              layout.isMobile ? ApotikBreakpoints.targetSentuhMinimum : 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: terpilih && aktifkan
            ? t.primarySoft
            : (aktifkan ? t.surface : t.surfaceMuted),
        borderRadius: BorderRadius.circular(ApotikDesignTokens.radiusControl),
        border: Border.all(
          color: terpilih && aktifkan ? t.primary : t.border,
          width: terpilih && aktifkan ? 1.6 : 1,
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
          if (!aktifkan) ...[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 13, color: t.textSecondary),
          ],
        ],
      ),
    );

    if (!aktifkan) {
      // Tooltip + label semantik menjelaskan MENGAPA terkunci.
      return Semantics(
        label: '${m.label}. ${m.alasanBelumDidukung}',
        excludeSemantics: true,
        child: Tooltip(message: m.alasanBelumDidukung, child: isi),
      );
    }
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
