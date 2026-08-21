import 'package:flutter/material.dart';

/// Satu pilihan pada menu aksi baris.
class AksiBaris {
  final IconData ikon;
  final String label;

  /// null berarti aksinya sedang tidak tersedia -- barisnya tetap TAMPIL tetapi
  /// redup, sehingga pengguna tahu aksi itu ada namun belum dapat dipakai
  /// sekarang. Menyembunyikannya justru membuat menu berubah-ubah isinya dan
  /// pengguna sulit membangun ingatan letak.
  final VoidCallback? onTap;

  /// Aksi yang merusak/menghapus diberi warna berbeda dan diletakkan terpisah.
  final bool merusak;

  const AksiBaris({
    required this.ikon,
    required this.label,
    required this.onTap,
    this.merusak = false,
  });
}

/// Tombol "..." yang membuka daftar aksi baris berikut ikon dan labelnya.
///
/// <b>Mengapa menggantikan deretan ikon.</b> Baris tabel CRUD dahulu memuat
/// empat sampai enam tombol ikon berjajar. Tiga masalahnya nyata: kolom Aksi
/// memakan lebar yang seharusnya milik data, ikon tanpa label hanya dapat
/// ditebak artinya (tooltip tidak muncul di layar sentuh), dan target sentuhnya
/// terlalu rapat sehingga salah tekan mudah terjadi -- berbahaya ketika salah
/// satunya Hapus.
///
/// Menu ini menampilkan ikon DAN label pada tiap pilihan, sehingga tidak ada
/// lagi yang perlu ditebak, dan aksi merusak dipisah oleh garis serta diberi
/// warna peringatan supaya tidak tertekan karena refleks.
class AksiBarisMenu extends StatelessWidget {
  final List<AksiBaris> aksi;

  /// Tooltip tombolnya; dibiarkan dapat diganti karena beberapa daftar memuat
  /// dokumen, bukan "data".
  final String tooltip;

  const AksiBarisMenu({
    super.key,
    required this.aksi,
    this.tooltip = 'Aksi lain',
  });

  @override
  Widget build(BuildContext context) {
    final tersedia = aksi.where((a) => a.onTap != null).toList();
    if (tersedia.isEmpty) {
      // Tidak ada satu pun aksi yang dapat dipakai -- tombolnya tidak
      // ditampilkan sama sekali daripada membuka menu kosong.
      return const SizedBox.shrink();
    }
    final warna = Theme.of(context).colorScheme;
    return PopupMenuButton<AksiBaris>(
      tooltip: tooltip,
      icon: const Icon(Icons.more_horiz, size: 20),
      position: PopupMenuPosition.under,
      onSelected: (a) => a.onTap?.call(),
      itemBuilder: (context) {
        final item = <PopupMenuEntry<AksiBaris>>[];
        final biasa = aksi.where((a) => !a.merusak).toList();
        final merusak = aksi.where((a) => a.merusak).toList();
        for (final a in biasa) {
          item.add(_butir(a, warna));
        }
        // Pemisah hanya bila memang ada keduanya; menu yang isinya cuma satu
        // kelompok tidak perlu garis yang tak memisahkan apa pun.
        if (biasa.isNotEmpty && merusak.isNotEmpty) {
          item.add(const PopupMenuDivider());
        }
        for (final a in merusak) {
          item.add(_butir(a, warna));
        }
        return item;
      },
    );
  }

  PopupMenuItem<AksiBaris> _butir(AksiBaris a, ColorScheme warna) {
    final aktif = a.onTap != null;
    final warnaIsi = !aktif
        ? warna.onSurface.withValues(alpha: 0.38)
        : (a.merusak ? warna.error : warna.onSurface);
    return PopupMenuItem<AksiBaris>(
      value: a,
      enabled: aktif,
      height: 40,
      child: Row(
        children: [
          Icon(a.ikon, size: 18, color: warnaIsi),
          const SizedBox(width: 12),
          Text(a.label, style: TextStyle(fontSize: 13, color: warnaIsi)),
        ],
      ),
    );
  }
}
