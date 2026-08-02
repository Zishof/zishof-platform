import 'package:core_hw/core_hw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/pengaturan_laci.dart';
import '../services/print_util.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import 'kasir_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Struk transaksi -- selalu tampil di layar (Fase 1, sama utk semua
/// platform), TAPI kini juga bisa dicetak sungguhan lewat [Printing.layoutPdf]
/// (pola sama persis dgn `price_tag_screen.dart`: render `pw.Document` lebar
/// kertas kasir 80mm, lalu serahkan ke dialog cetak OS -- BUKAN raw ESC/POS
/// spt Buka Laci, krn struk perlu tata letak/format, bukan sekadar 1 pulsa
/// byte). [tersinkron] membedakan status nyata transaksi: `true` = server
/// sudah mengonfirmasi (`bayar` sukses), `false` = baru tersimpan lokal
/// (offline-first, menunggu "Sinkronkan") -- sebelumnya kartu ini SELALU
/// generik "Transaksi Berhasil" tanpa membedakan keduanya, padahal itu beda
/// penting bagi kasir (transaksi offline BISA gagal disinkron nanti bila
/// stok berubah/produk dihapus, jadi kasir perlu tahu itu belum final).
class StrukScreen extends StatelessWidget {
  final String kode;
  final String waktu;
  final List<Map<String, dynamic>> item;
  final double total;
  final String metode;
  final double pajak;
  final bool tersinkron;

  const StrukScreen({
    super.key,
    required this.kode,
    required this.waktu,
    required this.item,
    required this.total,
    required this.metode,
    this.pajak = 0,
    this.tersinkron = true,
  });

  Future<void> _cetakStruk() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 10 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(Sesi.instance.tokoNama, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
            pw.SizedBox(height: 4),
            pw.Text(kode, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
            pw.Text(waktu, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 6),
            pw.Divider(),
            ...item.map((i) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(child: pw.Text('${i['nama']} x${i['qty']}', style: const pw.TextStyle(fontSize: 9))),
                      pw.Text(_formatRupiah.format((i['harga'] as num) * (i['qty'] as num)), style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                )),
            pw.Divider(),
            if (pajak > 0)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('Pajak', style: pw.TextStyle(fontSize: 9)), pw.Text(_formatRupiah.format(pajak), style: pw.TextStyle(fontSize: 9))],
              ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text(_formatRupiah.format(total), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [pw.Text('Metode', style: pw.TextStyle(fontSize: 9)), pw.Text(metode, style: pw.TextStyle(fontSize: 9))],
            ),
            if (Sesi.instance.pesanTerimaKasih.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text(Sesi.instance.pesanTerimaKasih, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
            ],
          ],
        ),
      ),
    );
    await cetakLangsungKePrinterDefault(dokumen: doc, nama: 'struk-$kode.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi Berhasil'), automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      tersinkron ? Icons.check_circle : Icons.cloud_off,
                      color: tersinkron ? AppColors.success : AppColors.warning,
                      size: 56,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tersinkron ? 'Berhasil & Tersinkron' : 'Tersimpan Offline',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: tersinkron ? AppColors.success : AppColors.warning),
                    ),
                    if (!tersinkron)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Belum terkirim ke server -- akan disinkron otomatis saat online, atau tekan Sinkronkan (F8).',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(Sesi.instance.tokoNama, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(kode, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    Text(waktu, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    const Divider(height: 24),
                    ...item.map((i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${i['nama']} x${i['qty']}')),
                              Text(_formatRupiah.format((i['harga'] as num) * (i['qty'] as num))),
                            ],
                          ),
                        )),
                    const Divider(height: 24),
                    if (pajak > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Pajak', style: TextStyle(color: Colors.black54)),
                          Text(_formatRupiah.format(pajak), style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(_formatRupiah.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Metode', style: TextStyle(color: Colors.black54)),
                        Text(metode),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (Sesi.instance.pesanTerimaKasih.isNotEmpty)
                      Text(Sesi.instance.pesanTerimaKasih, textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black54)),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _cetakStruk,
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: const Text('Cetak Struk'),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                        ),
                        if (defaultTargetPlatform == TargetPlatform.windows) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  await PengaturanLaci.instance.muat();
                                  await bukaLaciKasir(pinAlternatif: PengaturanLaci.instance.pinAlternatif, namaPrinter: PengaturanLaci.instance.namaPrinter);
                                } catch (e) {
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuka laci: $e')));
                                }
                              },
                              icon: const Icon(Icons.point_of_sale, size: 18),
                              label: const Text('Buka Laci'),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const KasirScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Transaksi Baru'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
