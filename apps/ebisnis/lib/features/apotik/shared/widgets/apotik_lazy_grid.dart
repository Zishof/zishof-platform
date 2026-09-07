import 'package:flutter/material.dart';

import '../../core/apotik_design_tokens.dart';

/// Grid responsif yang hanya membangun kartu yang berada di sekitar viewport.
///
/// Dipakai untuk katalog yang dapat berisi ratusan data. Tinggi kartu ikut
/// skala teks agar label keselamatan tidak terpotong pada setelan aksesibilitas.
class ApotikLazyGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double paddingHorizontal;
  final double paddingBottom;

  const ApotikLazyGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.paddingHorizontal = 14,
    this.paddingBottom = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final kolom = (constraints.maxWidth / 330).floor().clamp(1, 4);
      final jumlahBaris = (itemCount / kolom).ceil();
      // List per baris tetap lazy, tetapi tinggi setiap baris mengikuti kartu
      // tertinggi di baris tersebut. Dengan ini kartu biasa dapat rapat tanpa
      // memotong kartu ber-badge banyak atau teks aksesibilitas 200%.
      return ListView.builder(
        key: const PageStorageKey('apotik-lazy-medication-grid'),
        padding: EdgeInsets.fromLTRB(
            paddingHorizontal,
            4,
            paddingHorizontal,
            (paddingBottom - ApotikDesignTokens.gridSpacing)
                .clamp(0, 1000)
                .toDouble()),
        itemCount: jumlahBaris,
        itemBuilder: (context, baris) {
          return Padding(
            padding:
                const EdgeInsets.only(bottom: ApotikDesignTokens.gridSpacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var posisi = 0; posisi < kolom; posisi++) ...[
                  if (posisi > 0)
                    const SizedBox(width: ApotikDesignTokens.gridSpacing),
                  Expanded(
                    child: baris * kolom + posisi < itemCount
                        ? IndexedSemantics(
                            index: baris * kolom + posisi,
                            child: itemBuilder(context, baris * kolom + posisi),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        },
      );
    });
  }
}
