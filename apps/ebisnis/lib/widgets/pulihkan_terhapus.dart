import 'package:flutter/material.dart';

import '../services/master_offline.dart';
import '../theme/app_colors.dart';

/// Jendela "Data Terhapus (di perangkat)" — jalan pulang untuk penghapusan yang
/// dilakukan saat OFFLINE.
///
/// Penghapusan lokal bersifat LUNAK: barisnya tidak dibuang dari perangkat, hanya
/// ditandai sehingga hilang dari daftar (lihat `MasterOffline.terapkanLokal`). Tanpa
/// layar ini penanda itu tidak ada gunanya bagi pengguna — datanya tersimpan tetapi
/// tak terjangkau. Di sini setiap baris bertanda ditawarkan untuk dikembalikan.
///
/// Memulihkan berarti dua hal sekaligus, dan keduanya dikerjakan
/// `MasterOffline.pulihkanLokal`: penanda dilepas DAN perintah hapus yang masih
/// mengantre dibatalkan. Tanpa yang kedua, barisnya kembali tampil di layar tetapi
/// tetap terhapus di server begitu jaringan tersambung.
///
/// Baris yang penghapusannya SUDAH terkirim tidak muncul di sini — pemulihannya
/// memakai AuditTrails di sisi server, bukan salinan lokal.
class DialogPulihkanTerhapus extends StatefulWidget {
  const DialogPulihkanTerhapus({
    super.key,
    required this.cacheKey,
    required this.judul,
    required this.labelBaris,
    this.keteranganBaris,
    this.pemuat,
    this.pemulih,
  });

  /// Kunci cache daftar yang sedang dilihat layar pemanggil.
  final String cacheKey;

  /// Judul jendela, mis. "Akun Terhapus".
  final String judul;

  /// Teks utama satu baris, mis. kode + nama.
  final String Function(Map<String, dynamic> baris) labelBaris;

  /// Baris kedua yang lebih redup (opsional), mis. keterangan atau nominal.
  final String Function(Map<String, dynamic> baris)? keteranganBaris;

  /// Titik suntik untuk pengujian; bawaannya memakai [MasterOffline].
  final Future<List<Map<String, dynamic>>> Function(String cacheKey)? pemuat;
  final Future<bool> Function(String cacheKey, Object id, String? kunci)? pemulih;

  @override
  State<DialogPulihkanTerhapus> createState() => _DialogPulihkanTerhapusState();
}

class _DialogPulihkanTerhapusState extends State<DialogPulihkanTerhapus> {
  List<Map<String, dynamic>> _baris = const [];
  bool _memuat = true;
  int _dipulihkan = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final pemuat = widget.pemuat ?? MasterOffline.daftarTerhapusLokal;
    final hasil = await pemuat(widget.cacheKey);
    if (!mounted) return;
    setState(() {
      _baris = hasil;
      _memuat = false;
    });
  }

  Future<void> _pulihkan(Map<String, dynamic> baris) async {
    final id = baris['id'];
    if (id == null) return;
    final pemulih = widget.pemulih ??
        (String c, Object i, String? k) =>
            MasterOffline.pulihkanLokal(c, i, kunci: k);
    final kunci = baris['_kunci'] == null ? null : '${baris['_kunci']}';
    final berhasil = await pemulih(widget.cacheKey, id, kunci);
    if (!mounted) return;
    if (berhasil) _dipulihkan++;
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.judul),
      content: SizedBox(
        width: 520,
        child: _memuat
            ? const SizedBox(
                height: 90, child: Center(child: CircularProgressIndicator()))
            : _baris.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Tidak ada data terhapus yang masih tersimpan di perangkat ini. '
                      'Penghapusan yang sudah terkirim dipulihkan lewat AuditTrails di server.',
                    ),
                  )
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Baris berikut sudah ditandai terhapus tetapi penghapusannya '
                          'belum terkirim ke server, jadi masih dapat dikembalikan.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _baris.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final b = _baris[i];
                          final ket = widget.keteranganBaris?.call(b);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.delete_outline,
                                color: AppColors.danger, size: 20),
                            title: Text(widget.labelBaris(b),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: ket == null || ket.isEmpty
                                ? null
                                : Text(ket, style: const TextStyle(fontSize: 11.5)),
                            trailing: TextButton.icon(
                              onPressed: () => _pulihkan(b),
                              icon: const Icon(Icons.undo, size: 16),
                              label: const Text('Urungkan'),
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _dipulihkan),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

/// Buka jendela pemulihan; mengembalikan jumlah baris yang dipulihkan supaya
/// layar pemanggil tahu perlu memuat ulang daftarnya atau tidak.
Future<int> bukaPulihkanTerhapus(
  BuildContext context, {
  required String cacheKey,
  required String judul,
  required String Function(Map<String, dynamic> baris) labelBaris,
  String Function(Map<String, dynamic> baris)? keteranganBaris,
}) async {
  final hasil = await showDialog<int>(
    context: context,
    builder: (_) => DialogPulihkanTerhapus(
      cacheKey: cacheKey,
      judul: judul,
      labelBaris: labelBaris,
      keteranganBaris: keteranganBaris,
    ),
  );
  return hasil ?? 0;
}
