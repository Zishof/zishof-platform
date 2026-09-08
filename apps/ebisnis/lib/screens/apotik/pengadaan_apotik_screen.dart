import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_shell.dart';
import '../pengadaan_bast_screen.dart';
import '../pengadaan_bayar_screen.dart';
import '../pengadaan_po_screen.dart';
import '../pengadaan_pr_screen.dart';
import '../pengadaan_tagihan_screen.dart';
import 'pos_help.dart';

/// Pintu tunggal pengadaan obat. Penerimaan PBF lama sengaja tidak lagi
/// ditawarkan: stok pembelian hanya masuk melalui BAST yang telah disetujui.
class PengadaanApotikScreen extends StatelessWidget {
  const PengadaanApotikScreen({super.key});

  static const _tahap = <({
    String nomor,
    String judul,
    String uraian,
    IconData ikon,
  })>[
    (
      nomor: '01',
      judul: 'Permintaan Pembelian (PR)',
      uraian: 'Ajukan kebutuhan berdasarkan stok minimum dan rencana layanan.',
      ikon: Icons.assignment_outlined,
    ),
    (
      nomor: '02',
      judul: 'Pemesanan Pembelian (PO)',
      uraian: 'Pilih pemasok/PBF, harga, termin, lalu setujui pesanan.',
      ikon: Icons.receipt_long_outlined,
    ),
    (
      nomor: '03',
      judul: 'Penerimaan Barang (BAST)',
      uraian:
          'Catat batch, kedaluwarsa, jumlah diterima, dan hasil pemeriksaan.',
      ikon: Icons.inventory_2_outlined,
    ),
    (
      nomor: '04',
      judul: 'Terima Tagihan Vendor',
      uraian: 'Cocokkan tagihan dengan PO dan BAST yang sudah disetujui.',
      ikon: Icons.request_quote_outlined,
    ),
    (
      nomor: '05',
      judul: 'Pembayaran Vendor',
      uraian: 'Bayar tagihan tervalidasi dan pantau status pelunasannya.',
      ikon: Icons.payments_outlined,
    ),
  ];

  Widget _tujuan(int indeks) => switch (indeks) {
        0 => const PengadaanPrScreen(),
        1 => const PengadaanPoScreen(),
        2 => const PengadaanBastScreen(),
        3 => const PengadaanTagihanScreen(),
        _ => const PengadaanBayarScreen(),
      };

  void _buka(BuildContext context, int indeks) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => _tujuan(indeks)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppShell(
      menuAktif: MenuEBisnis.pengadaanApotik,
      judul: 'Pengadaan Obat',
      subjudul: 'Alur resmi PR → PO → BAST → Tagihan → Pembayaran Vendor',
      scrollable: false,
      actionsAppBar: [
        PosHelp.button(context, 'apotik_pengadaan', compact: true)
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary.withValues(alpha: .22)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.verified_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Satu jalur penerimaan yang dapat diaudit',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text(
                        'Penerimaan langsung PBF telah dihilangkan dari menu. '
                        'Barang pembelian masuk ke stok melalui BAST agar nomor PO, '
                        'batch, kedaluwarsa, tagihan, dan pembayaran tetap terlacak.',
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final lebar = c.maxWidth;
            final kolom = lebar >= 1100
                ? 3
                : lebar >= 680
                    ? 2
                    : 1;
            const jarak = 12.0;
            final lebarKartu = (lebar - (kolom - 1) * jarak) / kolom;
            return Wrap(
              spacing: jarak,
              runSpacing: jarak,
              children: [
                for (var i = 0; i < _tahap.length; i++)
                  SizedBox(
                    width: lebarKartu,
                    child: _KartuTahap(
                      data: _tahap[i],
                      terakhir: i == _tahap.length - 1,
                      onTap: () => _buka(context, i),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _KartuTahap extends StatelessWidget {
  final ({String nomor, String judul, String uraian, IconData ikon}) data;
  final bool terakhir;
  final VoidCallback onTap;

  const _KartuTahap(
      {required this.data, required this.terakhir, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: AppColors.cardBgOf(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                child: Icon(data.ikon, size: 20),
              ),
              const Spacer(),
              Text(data.nomor,
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2)),
            ]),
            const SizedBox(height: 14),
            Text(data.judul,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(data.uraian,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Row(children: [
              Text(terakhir ? 'Buka pembayaran' : 'Buka tahap',
                  style: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
            ]),
          ]),
        ),
      ),
    );
  }
}
