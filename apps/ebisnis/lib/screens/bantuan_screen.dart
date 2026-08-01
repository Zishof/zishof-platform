import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';

/// Layar Bantuan (F1) -- padanan tombol "F1 Bantuan" pada toolbar referensi
/// Electron. Isinya statis (daftar pintasan keyboard + info dasar), bukan
/// artikel bantuan per-halaman spt katalog Bantuan modul lain di monolith --
/// cukup utk kasir yang lupa satu-dua tombol saat sedang melayani pembeli.
class BantuanScreen extends StatelessWidget {
  const BantuanScreen({super.key});

  static const _pintasan = [
    ('F2', 'Bayar', 'Selesaikan pembayaran & cetak struk'),
    ('F3', 'Tahan', 'Simpan keranjang saat ini utk dilanjutkan nanti'),
    ('F4', 'Metode Pembayaran', 'Buka pilihan metode bayar (tunai/non-tunai)'),
    ('F5', 'Pilih Member', 'Cari & pilih anggota utk transaksi ini'),
    ('F6', 'Buka Laci', 'Buka laci kasir secara manual (mis. tukar uang)'),
    ('F7', 'Fokus Keranjang', 'Sembunyikan katalog produk, lebarkan panel keranjang'),
    ('F8', 'Sinkronkan', 'Kirim transaksi tertunda ke server sekarang'),
    ('F9', 'Layar Pelanggan', 'Buka tampilan layar kedua utk pelanggan'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionCard(
            judul: 'Pintasan Keyboard',
            child: Column(
              children: _pintasan
                  .map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.pageBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(p.$1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(p.$3, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            judul: 'Perlu Bantuan Lebih Lanjut?',
            child: const Text(
              'Hubungi admin/supervisor toko Anda, atau tim dukungan eBisnis bila '
              'kendala terkait server/sinkronisasi data.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
