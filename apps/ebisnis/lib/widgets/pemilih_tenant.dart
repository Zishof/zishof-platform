import 'package:flutter/material.dart';

import '../services/pengikatan_tenant.dart';

/// Pemilih usaha (tenant) untuk pengguna yang terdaftar pada lebih dari satu.
///
/// Muncul saat login, hanya bila server menjawab `TENANT_SELECTION_REQUIRED`.
/// Pengguna dengan satu usaha tidak pernah melihatnya — tenantnya dipilih
/// otomatis oleh server (§7.1 butir 3).
///
/// **Tidak dapat ditutup begitu saja.** Pengguna yang punya beberapa usaha
/// harus menyebut yang mana; menebak salah satu berarti ia bekerja pada
/// perusahaan yang keliru tanpa pernah tahu (§7.1 butir 4). Membatalkan berarti
/// membatalkan login, dan itu dinyatakan terang-terangan lewat tombol
/// "Keluar".
///
/// **Usaha yang sedang tidak dapat dipakai tetap ditampilkan** berikut
/// alasannya, hanya tidak dapat dipilih. Menyembunyikannya menghasilkan daftar
/// yang tampak kehilangan data, dan pengguna tidak akan tahu apakah ia harus
/// menunggu atau menghubungi admin.
class PemilihTenant extends StatelessWidget {
  const PemilihTenant._({required this.daftar});

  final List<RingkasanTenant> daftar;

  /// Tampilkan pemilihnya. Mengembalikan `tenantId` yang dipilih, atau `null`
  /// bila pengguna memilih keluar.
  static Future<int?> pilih(
      BuildContext context, List<RingkasanTenant> daftar) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PemilihTenant._(daftar: daftar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teks = Theme.of(context).textTheme;
    return PopScope(
      // Tombol kembali tidak boleh menutup dialog ini: keluar dari sini tanpa
      // memilih akan meninggalkan pengguna terautentikasi tanpa tenant.
      canPop: false,
      child: AlertDialog(
        title: const Text('Pilih usaha'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Akun Anda terdaftar pada beberapa usaha. Pilih satu untuk '
                  'dipakai di perangkat ini.',
                  style: teks.bodyMedium,
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: daftar.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _baris(context, daftar[i]),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  Widget _baris(BuildContext context, RingkasanTenant t) {
    final teks = Theme.of(context).textTheme;
    final warna = Theme.of(context).colorScheme;
    final bisa = t.dapatDipakai;

    final keterangan = <String>[];
    if (t.kode.isNotEmpty) keterangan.add(t.kode);
    if (t.peran.isNotEmpty) keterangan.add(t.peran);

    return ListTile(
      enabled: bisa,
      leading: Icon(
        bisa ? Icons.storefront : Icons.pause_circle_outline,
        color: bisa ? warna.primary : Theme.of(context).disabledColor,
      ),
      title: Text(
        t.nama.isEmpty ? '(tanpa nama)' : t.nama,
        style: teks.titleSmall,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (keterangan.isNotEmpty)
            Text(keterangan.join(' · '), style: teks.bodySmall),
          if (!bisa)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                t.alasanTidakDapat,
                style: teks.bodySmall?.copyWith(color: warna.error),
              ),
            ),
        ],
      ),
      trailing: bisa ? const Icon(Icons.chevron_right) : null,
      onTap: bisa ? () => Navigator.of(context).pop(t.id) : null,
    );
  }
}
