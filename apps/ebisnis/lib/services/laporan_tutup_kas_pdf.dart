import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PDF dan format spooler harus memakai ukuran kertas thermal yang sama.
Future<(pw.Document, PdfPageFormat)> buatPdfLaporanTutupKas(
    Map<String, dynamic> laporan,
    {required double lebarMm}) async {
  final rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  num angka(String key) => laporan[key] is num ? laporan[key] as num : 0;
  String teks(String key) => laporan[key]?.toString() ?? '';
  final metode = ((laporan['metodePembayaran'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final lebar = lebarMm * PdfPageFormat.mm;
  final dokumen = pw.Document();

  // Ruang margin aman untuk printer thermal 58mm & 80mm agar digit kanan tidak terpotong
  final marginKiriMm = lebarMm <= 58 ? 2.5 : 4.0;
  final marginKananMm = lebarMm <= 58 ? 5.5 : 7.0;
  final ukuranFont = lebarMm <= 58 ? 7.0 : 8.0;

  pw.Widget baris(String nama, String nilai, {bool tebal = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                nama,
                style: pw.TextStyle(
                  fontSize: ukuranFont,
                  fontWeight: tebal ? pw.FontWeight.bold : null,
                ),
              ),
            ),
            pw.SizedBox(width: 4),
            pw.SizedBox(
              height: ukuranFont + 2,
              width:
                  (lebar - (marginKiriMm + marginKananMm) * PdfPageFormat.mm) *
                      0.48,
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  nilai,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: ukuranFont,
                    fontWeight: tebal ? pw.FontWeight.bold : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  final format = PdfPageFormat(
    lebar,
    // Roll thermal mengikuti tinggi isi, termasuk nama metode yang membungkus.
    double.infinity,
    marginLeft: marginKiriMm * PdfPageFormat.mm,
    marginRight: marginKananMm * PdfPageFormat.mm,
    marginTop: 3 * PdfPageFormat.mm,
    marginBottom: 3 * PdfPageFormat.mm,
  );
  dokumen.addPage(pw.Page(
    pageFormat: format,
    build: (_) =>
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(
          child: pw.Text('LAPORAN TUTUP KAS',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
      pw.Center(
          child: pw.Text(teks('namaToko'),
              style: pw.TextStyle(fontSize: ukuranFont + 0.5))),
      pw.Divider(thickness: 0.5),
      pw.Text('Kasir : ${teks('namaKasir')}',
          style: pw.TextStyle(fontSize: ukuranFont)),
      pw.Text('Buka  : ${teks('waktuBuka')}',
          style: pw.TextStyle(fontSize: ukuranFont)),
      pw.Text('Tutup : ${teks('waktuTutup')}',
          style: pw.TextStyle(fontSize: ukuranFont)),
      pw.Divider(thickness: 0.5),
      baris('Modal Awal', rupiah.format(angka('modalAwal'))),
      baris('Penjualan Tunai', rupiah.format(angka('penjualanTunai'))),
      baris('Kas Seharusnya', rupiah.format(angka('kasSeharusnya'))),
      baris('Jumlah Kas Tunai', rupiah.format(angka('jumlahKasTunai'))),
      baris('Selisih', rupiah.format(angka('selisih')), tebal: true),
      pw.Divider(thickness: 0.5),
      baris('Retur Penjualan', rupiah.format(angka('returPenjualan'))),
      baris('Biaya (${angka('jumlahBiaya')}x)', rupiah.format(angka('biaya'))),
      pw.Divider(thickness: 0.5),
      baris('Piutang (${angka('jumlahTransaksiPiutang')}x)',
          rupiah.format(angka('piutang'))),
      pw.Divider(thickness: 0.5),
      ...metode.expand((m) => [
            pw.Text(m['nama']?.toString() ?? '-',
                style: pw.TextStyle(
                    fontSize: ukuranFont, fontWeight: pw.FontWeight.bold)),
            baris('${m['jumlahTransaksi'] ?? 0}x Penerimaan',
                rupiah.format(m['penerimaan'] ?? 0)),
            baris('Retur', rupiah.format(m['retur'] ?? 0)),
            baris('Total ${m['nama'] ?? ''}', rupiah.format(m['total'] ?? 0),
                tebal: true),
          ]),
      pw.Divider(thickness: 0.5),
      baris('Jumlah Transaksi', angka('jumlahTransaksi').toString(),
          tebal: true),
      baris('Total Transaksi', rupiah.format(angka('totalTransaksi')),
          tebal: true),
    ]),
  ));
  await dokumen.save();
  return (dokumen, dokumen.document.pdfPageList.pages.single.pageFormat);
}
