import 'package:flutter/material.dart';

import '../screens/bantuan_kontekstual.dart';
import '../screens/bantuan_screen.dart';

/// Tombol bantuan mengambang: SATU tombol bulat "?" yang membuka menu pilihan.
///
/// Sebelumnya tiap layar memasang sendiri ikon `Icons.help_outline` di tempat yang
/// berbeda-beda, dan sebagian besar layar tidak punya jalan ke bantuan sama sekali.
/// Pola ini menyamakan keduanya sekaligus menjaga layar utama tetap lapang: hanya satu
/// tombol yang terlihat, isinya baru muncul saat diketuk.
///
/// Pilihan yang ditawarkan mengikuti ketersediaan isi, bukan dipaksakan:
/// * **Bantuan Halaman Ini** dan **Tanya Jawab** hanya muncul bila menu yang sedang
///   dibuka memang punya entri pada [spesifikasiBantuanMenu]; Tanya Jawab menuntut
///   `tanyaJawabTambahan` yang tidak kosong.
/// * **Semua Bantuan** selalu ada sebagai jalan keluar.
///
/// Sengaja TIDAK memakai [FloatingActionButton]: layar tertentu sudah punya FAB sendiri,
/// dan dua FAB dalam satu pohon widget memicu bentrok `heroTag` saat transisi halaman.
class BantuanFab extends StatelessWidget {
  /// Nama enum menu yang sedang aktif (mis. `kasir`), dipakai sebagai kunci pencarian
  /// pada [spesifikasiBantuanMenu].
  final String menuId;

  /// Judul halaman, ditampilkan sebagai judul artikel bantuan.
  final String judul;

  const BantuanFab({super.key, required this.menuId, required this.judul});

  void _buka(BuildContext context, {String? id, String? cariAwal}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BantuanScreen(
        menuId: id,
        menuJudul: id == null ? null : judul,
        cariAwal: cariAwal,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final spesifikasi = spesifikasiBantuanMenu[menuId];
    final adaTanyaJawab =
        spesifikasi != null && spesifikasi.tanyaJawabTambahan.isNotEmpty;

    return PopupMenuButton<String>(
      tooltip: 'Bantuan',
      offset: const Offset(0, -8),
      position: PopupMenuPosition.over,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (pilihan) {
        switch (pilihan) {
          case 'bantuan':
            _buka(context, id: menuId);
            break;
          case 'qa':
            _buka(context, id: menuId, cariAwal: 'Tanya Jawab');
            break;
          default:
            _buka(context);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        if (spesifikasi != null)
          const PopupMenuItem<String>(
            value: 'bantuan',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.menu_book_outlined),
              title: Text('Bantuan Halaman Ini'),
              subtitle: Text('Panduan modul yang sedang dibuka'),
            ),
          ),
        if (adaTanyaJawab)
          const PopupMenuItem<String>(
            value: 'qa',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.forum_outlined),
              title: Text('Tanya Jawab'),
              subtitle: Text('Pertanyaan yang sering muncul di halaman ini'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'semua',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.library_books_outlined),
            title: Text('Semua Bantuan'),
            subtitle: Text('Seluruh panduan, menurut peran dan per modul'),
          ),
        ),
      ],
      child: Semantics(
        button: true,
        label: 'Bantuan',
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1D4ED8),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: .38),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
