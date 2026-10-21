import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final _formatRupiahPdf =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatAngkaPdf = NumberFormat.decimalPattern('id_ID');

/// Menghasilkan dokumen PDF berformat Struk Thermal (58mm / 80mm)
/// untuk Rekap Penjualan Item/Produk Harian di POS Kasir.
Future<(pw.Document, PdfPageFormat)> buatPdfRekapPenjualanItemThermal(
  Map<String, dynamic> dataLaporan, {
  double lebarMm = 58.0,
}) async {
  final formatHalaman = PdfPageFormat(
    lebarMm * PdfPageFormat.mm,
    double.infinity,
    marginAll: 4 * PdfPageFormat.mm,
  );

  final doc = pw.Document();

  final namaToko = (dataLaporan['tokoNama'] as String?)?.isNotEmpty == true
      ? dataLaporan['tokoNama'] as String
      : 'TOKOQU';
  final tanggal = (dataLaporan['tanggal'] as String?) ??
      DateFormat('yyyy-MM-dd').format(DateTime.now());
  final kasir = (dataLaporan['kasirNama'] as String?) ?? 'Semua Kasir';
  final wktCetak = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

  final ringkasan =
      (dataLaporan['ringkasan'] as Map?)?.cast<String, dynamic>() ?? {};
  final totalItem = (ringkasan['totalItem'] as num?)?.toInt() ?? 0;
  final totalQty = (ringkasan['totalQty'] as num?)?.toDouble() ?? 0;
  final totalOmzet = (ringkasan['totalPenjualan'] as num?)?.toDouble() ?? 0;

  final List itemsRaw = (dataLaporan['data'] as List?) ?? [];
  final items = itemsRaw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  final double ukuranFont = lebarMm >= 75 ? 9.0 : 7.5;
  final double ukuranFontKecil = lebarMm >= 75 ? 8.0 : 6.5;

  doc.addPage(
    pw.Page(
      pageFormat: formatHalaman,
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Header Toko
            pw.Center(
              child: pw.Text(
                namaToko.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: ukuranFont + 3,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'REKAP PENJUALAN ITEM HARIAN',
                style: pw.TextStyle(
                  fontSize: ukuranFont,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Divider(thickness: 0.8),

            // Metadata
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Tanggal : $tanggal',
                    style: pw.TextStyle(fontSize: ukuranFontKecil)),
                pw.Text('Kasir : $kasir',
                    style: pw.TextStyle(fontSize: ukuranFontKecil)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text('Dicetak : $wktCetak',
                style: pw.TextStyle(fontSize: ukuranFontKecil)),
            pw.Divider(thickness: 0.8),

            // Daftar Item Terjual
            for (int i = 0; i < items.length; i++) ...[
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${i + 1}. ${(items[i]['nama'] as String?) ?? 'Produk'}',
                    style: pw.TextStyle(
                      fontSize: ukuranFontKecil + 0.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    maxLines: 2,
                  ),
                  pw.SizedBox(height: 1),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '   ${_formatAngkaPdf.format((items[i]['qty'] as num?)?.toDouble() ?? 0)} ${(items[i]['satuan'] as String?) ?? 'Pcs'} x ${_formatRupiahPdf.format((items[i]['hargaRata'] as num?)?.toDouble() ?? 0)}',
                        style: pw.TextStyle(fontSize: ukuranFontKecil),
                      ),
                      pw.Text(
                        _formatRupiahPdf.format(
                            (items[i]['total'] as num?)?.toDouble() ?? 0),
                        style: pw.TextStyle(
                          fontSize: ukuranFontKecil,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
            ],

            pw.Divider(thickness: 0.8),

            // Total Ringkasan
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Jenis Item:',
                    style: pw.TextStyle(fontSize: ukuranFontKecil)),
                pw.Text('$totalItem produk',
                    style: pw.TextStyle(fontSize: ukuranFontKecil)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Qty Terjual:',
                    style: pw.TextStyle(
                        fontSize: ukuranFontKecil,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text('${_formatAngkaPdf.format(totalQty)} item',
                    style: pw.TextStyle(
                        fontSize: ukuranFontKecil,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL PENJUALAN:',
                  style: pw.TextStyle(
                    fontSize: ukuranFont,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _formatRupiahPdf.format(totalOmzet),
                  style: pw.TextStyle(
                    fontSize: ukuranFont,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.Divider(thickness: 0.8),
            pw.SizedBox(height: 10),

            // Kolom Tanda Tangan
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text('Kasir,',
                        style: pw.TextStyle(fontSize: ukuranFontKecil)),
                    pw.SizedBox(height: 24),
                    pw.Text('( $kasir )',
                        style: pw.TextStyle(
                            fontSize: ukuranFontKecil,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('Supervisor,',
                        style: pw.TextStyle(fontSize: ukuranFontKecil)),
                    pw.SizedBox(height: 24),
                    pw.Text('( ................... )',
                        style: pw.TextStyle(fontSize: ukuranFontKecil)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
          ],
        );
      },
    ),
  );

  return (doc, formatHalaman);
}

/// Menghasilkan dokumen PDF format standar dokumen A4.
Future<pw.Document> buatPdfRekapPenjualanItemA4(
  Map<String, dynamic> dataLaporan,
) async {
  final doc = pw.Document();

  final namaToko = (dataLaporan['tokoNama'] as String?)?.isNotEmpty == true
      ? dataLaporan['tokoNama'] as String
      : 'TOKOQU';
  final tanggal = (dataLaporan['tanggal'] as String?) ??
      DateFormat('yyyy-MM-dd').format(DateTime.now());
  final kasir = (dataLaporan['kasirNama'] as String?) ?? 'Semua Kasir';
  final wktCetak = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

  final ringkasan =
      (dataLaporan['ringkasan'] as Map?)?.cast<String, dynamic>() ?? {};
  final totalQty = (ringkasan['totalQty'] as num?)?.toDouble() ?? 0;
  final totalDiskon = (ringkasan['totalDiskon'] as num?)?.toDouble() ?? 0;
  final totalOmzet = (ringkasan['totalPenjualan'] as num?)?.toDouble() ?? 0;

  final List itemsRaw = (dataLaporan['data'] as List?) ?? [];
  final items = itemsRaw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(namaToko.toUpperCase(),
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('LAPORAN REKAP PENJUALAN PRODUK HARIAN',
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Tanggal: $tanggal',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Kasir: $kasir',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Dicetak: $wktCetak',
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1),
          pw.SizedBox(height: 6),
        ],
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: const [
            'No',
            'Kode',
            'Nama Produk',
            'Kategori',
            'Satuan',
            'Qty',
            'Harga Rata-rata',
            'Diskon',
            'Total (Rp)'
          ],
          data: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final r = entry.value;
            return [
              '$idx',
              '${r['kode'] ?? ''}',
              '${r['nama'] ?? ''}',
              '${r['kategori'] ?? ''}',
              '${r['satuan'] ?? 'Pcs'}',
              _formatAngkaPdf.format((r['qty'] as num?)?.toDouble() ?? 0),
              _formatRupiahPdf.format((r['hargaRata'] as num?)?.toDouble() ?? 0),
              _formatRupiahPdf.format((r['diskon'] as num?)?.toDouble() ?? 0),
              _formatRupiahPdf.format((r['total'] as num?)?.toDouble() ?? 0),
            ];
          }).toList(),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle:
              pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {
            0: pw.Alignment.center,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
            8: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Text('Total Jenis Item: ${items.length}',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Total Qty Terjual: ${_formatAngkaPdf.format(totalQty)}',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Total Diskon: ${_formatRupiahPdf.format(totalDiskon)}',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('Total Penjualan: ${_formatRupiahPdf.format(totalOmzet)}',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900)),
            ],
          ),
        ),
      ],
    ),
  );

  return doc;
}
