import 'package:flutter/material.dart';

/// Mencegah navigasi yang membuang form checkout sebelum Tahan/Bayar berhasil.
/// Tidak menyimpan transaksi dan tidak pernah menganggap pembayaran sukses.
///
/// Sesuai **ATURAN MUTLAK 388** (`/docs/AGENTS.md`):
/// - Tombol `Kembali ke keranjang` pada dialog peringatan wajib memanggil
///   [onKembaliKeKeranjang] (bila tersedia) agar pengguna yang sedang berada
///   pada tab lain di dalam `IndexedStack` Desktop (misalnya `Pesanan`)
///   langsung diarahkan kembali ke tab `Kasir/POS` dan tidak terjebak di luar
///   layar Kasir.
class PengamanKeranjang extends InheritedWidget {
  final bool Function() adaBarang;
  final VoidCallback? onKembaliKeKeranjang;

  const PengamanKeranjang({
    super.key,
    required this.adaBarang,
    this.onKembaliKeKeranjang,
    required super.child,
  });

  /// Mengembalikan `true` bila di pohon widget di atas [context] terdapat
  /// [PengamanKeranjang] yang keranjangnya sedang berisi barang.
  static bool adaBarangAktif(BuildContext context) {
    final penjaga = context.getInheritedWidgetOfExactType<PengamanKeranjang>();
    return penjaga?.adaBarang() == true;
  }

  static bool cegahKeluar(BuildContext context) {
    final penjaga = context.getInheritedWidgetOfExactType<PengamanKeranjang>();
    if (penjaga?.adaBarang() != true) return false;
    tampilkanPeringatan(context, onKembaliKeKeranjang: penjaga?.onKembaliKeKeranjang);
    return true;
  }

  static void tampilkanPeringatan(
    BuildContext context, {
    VoidCallback? onKembaliKeKeranjang,
  }) {
    final penjaga = context.getInheritedWidgetOfExactType<PengamanKeranjang>();
    final aksiKembali = onKembaliKeKeranjang ?? penjaga?.onKembaliKeKeranjang;
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
            onPressed: () {
              Navigator.pop(dialogContext);
              aksiKembali?.call();
            },
            child: const Text('Kembali ke keranjang'),
          )
        ],
      ),
    );
  }

  @override
  bool updateShouldNotify(PengamanKeranjang oldWidget) => true;
}
