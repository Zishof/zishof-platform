import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../sesi.dart';

/// Util cetak/ekspor bersama layar varian Inventory & Sales (SCR-12..16 dkk):
/// PDF client-side (pola voucher P3, package pdf+printing) + CSV client-side
/// (pola persis `LaporanDetailScreen._eksporCsv`). Header PDF memuat konteks
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
  }) async {
    final doc = pw.Document();
    final waktu = DateTime.now().toString().split('.').first;
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(judul,
            style:
                pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
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
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: namaFile);
  }

  static Future<void> eksporCsv({
    required BuildContext context,
    required String namaFile,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    String escapeCsv(String s) {
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final buffer = StringBuffer();
    buffer.writeln(headers.map(escapeCsv).join(','));
    for (final r in rows) {
      buffer.writeln(r.map(escapeCsv).join(','));
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan CSV',
          fileName: namaFile,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['csv']);
      if (path == null) return;
      // Desktop hanya mengembalikan path (bytes belum tertulis); mobile sudah
      // menulis via `bytes` -- tulis ulang idempoten (pola LaporanDetailScreen).
      await File(path).writeAsBytes(bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('CSV disimpan: $path')));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor CSV: $e')));
      }
    }
  }
}
