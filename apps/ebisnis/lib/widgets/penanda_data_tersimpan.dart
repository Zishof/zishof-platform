import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// <h3>Penanda "angka ini dari salinan tersimpan, bukan data terkini".</h3>
///
/// Dipasang di layar LAPORAN yang menyajikan angka uang/rekap dari cache
/// lokal saat server tak terjangkau. Untuk daftar master, keterlambatan
/// data tidak berbahaya; untuk laporan keuangan BISA menyesatkan bila user
/// mengira angkanya terkini -- karena itu keadaannya dinyatakan terang-
/// terangan, bukan disembunyikan.
///
/// Tampil hanya saat [tampil] true (yakni emisi lokal dipakai dan pembaruan
/// server belum tiba), memudar masuk supaya tidak mengejutkan.
class PenandaDataTersimpan extends StatelessWidget {
  final bool tampil;

  /// Kapan salinan ini terakhir diperbarui, bila diketahui.
  final DateTime? diperbaruiPada;

  const PenandaDataTersimpan(
      {super.key, required this.tampil, this.diperbaruiPada});

  String get _keterangan {
    final w = diperbaruiPada;
    if (w == null) return 'Menampilkan salinan tersimpan di perangkat.';
    final t = '${w.day.toString().padLeft(2, '0')}-'
        '${w.month.toString().padLeft(2, '0')}-${w.year} '
        '${w.hour.toString().padLeft(2, '0')}:'
        '${w.minute.toString().padLeft(2, '0')}';
    return 'Menampilkan salinan tersimpan ($t).';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: !tampil
          ? const SizedBox.shrink(key: ValueKey('tanpa-penanda'))
          : Container(
              key: const ValueKey('penanda-tersimpan'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.history_toggle_off,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_keterangan Angka belum tentu mencerminkan '
                    'transaksi terbaru — sambungkan ke server lalu muat ulang.',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.warning),
                  ),
                ),
              ]),
            ),
    );
  }
}
