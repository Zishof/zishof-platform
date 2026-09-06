import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../sesi.dart';
import '../../services/simple_xlsx.dart';

/// Util cetak/ekspor bersama layar varian Inventory & Sales (SCR-12..16 dkk):
/// PDF client-side (pola voucher P3, package pdf+printing) + XLSX client-side
/// (workbook OOXML asli, bukan CSV berganti ekstensi). Header PDF memuat konteks
/// wajib paritas (pengguna, toko, waktu cetak, parameter) -- Matriks 48 layar:
/// "cetak membawa parameter, jumlah baris, pengguna, waktu".
class CetakUtilIs {
  CetakUtilIs._();

  static Future<void> cetakPdfTabel({
    required String judul,
    required String parameter,
    required List<String> headers,
    required List<List<String>> rows,
    required String namaFile,
    String? barisTotal,
    /// Lebar RELATIF per kolom (indeks -> bobot). Opsional: tanpa ini
    /// TableHelper membagi lebar menurut isi terpanjang, dan judul yang panjang
    /// menyedot ruang dari tetangganya sampai kode barang terbelah dua baris.
    Map<int, double>? lebarKolom,
  }) async {
    final doc = pw.Document();
    final waktu = DateTime.now().toString().split('.').first;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(judul,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(
            'Toko: ${Sesi.instance.tokoNama.isEmpty ? "(global)" : Sesi.instance.tokoNama}'
            '  ·  Pengguna: ${Sesi.instance.userId}  ·  Dicetak: $waktu',
            style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Parameter: $parameter  ·  Jumlah baris: ${rows.length}',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          columnWidths:
              lebarKolom?.map((i, w) => MapEntry(i, pw.FlexColumnWidth(w))),
          headerStyle:
              pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignment: pw.Alignment.centerLeft,
        ),
        if (barisTotal != null) ...[
          pw.SizedBox(height: 6),
          pw.Text(barisTotal,
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ],
    ));
    final bytes = await doc.save();
    // JAHITAN UJI, sengaja sesempit ini.
    //
    // Printing.layoutPdf membuka dialog cetak milik SISTEM OPERASI. Dialog itu
    // bukan permukaan Flutter, jadi renderView.layer.toImage() tidak dapat
    // memotretnya -- dan tanpa jalan lain, jalur cetak menjadi satu-satunya
    // bagian aplikasi yang tidak pernah bisa diverifikasi otomatis. Sembilan
    // dari 48 layar legacy adalah hasil cetak, jadi itu lubang yang besar.
    //
    // Nilai ini hanya terisi bila build diberi --dart-define=POS_TEST_PDF_DIR.
    // Build produksi tidak pernah memberinya, sehingga cabang ini mati di sana.
    const dirUji = String.fromEnvironment('POS_TEST_PDF_DIR');
    if (dirUji.isNotEmpty) {
      final f = File('$dirUji${Platform.pathSeparator}$namaFile');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      return;
    }
    await Printing.layoutPdf(onLayout: (_) => bytes, name: namaFile);
  }

  static Future<void> eksporExcel({
    required BuildContext context,
    required String namaFile,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    try {
      final bytes = buildSimpleXlsx(
        sheetName: 'Data',
        headers: headers,
        rows: rows,
      );
      final fileName = namaFile.replaceFirst(RegExp(r'\.[^.]+$'), '.xlsx');
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan Excel',
          fileName: fileName,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['xlsx']);
      if (path == null) return;
      // Desktop hanya mengembalikan path (bytes belum tertulis); mobile sudah
      // menulis via `bytes` -- tulis ulang idempoten (pola LaporanDetailScreen).
      await File(path).writeAsBytes(bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Excel disimpan: $path')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengekspor Excel: $e')));
      }
    }
  }
}
