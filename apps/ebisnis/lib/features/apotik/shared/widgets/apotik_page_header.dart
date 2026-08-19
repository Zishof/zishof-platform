import 'package:flutter/material.dart';

import '../../core/apotik_breakpoints.dart';
import '../../core/apotik_design_tokens.dart';

/// Judul halaman + subjudul + aksi, konsisten lintas layar apotik.
/// Pada mobile aksi turun ke baris kedua agar judul tidak terpotong.
class ApotikPageHeader extends StatelessWidget {
  final String judul;
  final String? subjudul;
  final List<Widget> aksi;
  final Widget? kiri;

  const ApotikPageHeader({
    super.key,
    required this.judul,
    this.subjudul,
    this.aksi = const [],
    this.kiri,
  });

  @override
  Widget build(BuildContext context) {
    final t = ApotikDesignTokens.of(context);
    return ApotikResponsive(
      builder: (context, layout) {
        final teks = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(judul,
                style: TextStyle(
                    fontSize: layout.isMobile ? 19 : 23,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary)),
            if (subjudul != null) ...[
              const SizedBox(height: 2),
              Text(subjudul!,
                  style: TextStyle(fontSize: 13, color: t.textSecondary)),
            ],
          ],
        );
        final barisAksi = Wrap(spacing: 8, runSpacing: 8, children: aksi);
        return Padding(
          padding: EdgeInsets.fromLTRB(ApotikBreakpoints.paddingHalaman(layout),
              16, ApotikBreakpoints.paddingHalaman(layout), 12),
          child: layout.isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (kiri != null) ...[kiri!, const SizedBox(width: 10)],
                      Expanded(child: teks),
                    ]),
                    if (aksi.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      barisAksi,
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (kiri != null) ...[kiri!, const SizedBox(width: 12)],
                    Expanded(child: teks),
                    barisAksi,
                  ],
                ),
        );
      },
    );
  }
}
