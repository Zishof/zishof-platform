import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Semua jenis laporan tetap dapat dipilih tanpa menggeser tab tersembunyi.
class NavigasiLaporanTransaksi extends StatelessWidget {
  static const jenisLaporan = <String>[
    'Report Order',
    'Report Sesi',
    'Transaksi Per Kasir',
    'Report Payment',
    'Penjualan per Kasir',
    'Penerimaan per Kasir',
    'Rincian Produk',
  ];
  final TabController controller;
  const NavigasiLaporanTransaksi({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1400) {
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: DropdownButtonFormField<int>(
                  key: const Key('pemilih-jenis-laporan-transaksi'),
                  value: controller.index,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Laporan',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var index = 0; index < jenisLaporan.length; index++)
                      DropdownMenuItem(
                        value: index,
                        child: Text(jenisLaporan[index]),
                      ),
                  ],
                  onChanged: (index) {
                    if (index != null) controller.animateTo(index);
                  },
                ),
              ),
            );
          }
          return TabBar(
            controller: controller,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabs: [for (final label in jenisLaporan) Tab(text: label)],
          );
        },
      );
}
