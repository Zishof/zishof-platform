import 'package:flutter/material.dart';

/// Mencegah navigasi yang membuang form checkout sebelum Tahan/Bayar berhasil.
/// Tidak menyimpan transaksi dan tidak pernah menganggap pembayaran sukses.
class PengamanKeranjang extends InheritedWidget {
  final bool Function() adaBarang;
  const PengamanKeranjang(
      {super.key, required this.adaBarang, required super.child});

  static bool cegahKeluar(BuildContext context) {
    final penjaga = context.getInheritedWidgetOfExactType<PengamanKeranjang>();
    if (penjaga?.adaBarang() != true) return false;
    tampilkanPeringatan(context);
    return true;
  }

  static void tampilkanPeringatan(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keranjang masih berisi barang'),
        content: const Text(
            'Tetap di Kasir agar barang dan pilihan pembayaran tidak hilang. '
            'Gunakan Tahan dan pastikan berhasil sebelum berpindah halaman atau keluar. '
            'Jika penyimpanan sedang bermasalah, tutup pesan ini dan hubungi admin; '
            'jangan mengulang pembayaran sebelum status transaksi diperiksa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kembali ke keranjang'),
          )
        ],
      ),
    );
  }

  @override
  bool updateShouldNotify(PengamanKeranjang oldWidget) => true;
}
