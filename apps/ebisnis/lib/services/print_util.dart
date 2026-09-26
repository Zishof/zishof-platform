import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<bool> printerKasirAktifTerdeteksi({String? namaPrinter}) async {
  final target = namaPrinter?.trim();
  try {
    final printers = await Printing.listPrinters();
    if (printers.isEmpty) return false;

    bool siapUntukRaw(Printer p) =>
        p.isAvailable && !_printerEksporPdfSistem(p.name);

    if (target != null && target.isNotEmpty) {
      return printers.any((p) => p.name == target && siapUntukRaw(p));
    }
    return printers.any((p) => p.isDefault && siapUntukRaw(p));
  } catch (_) {
    // Jika API daftar printer gagal, biarkan jalur RAW mencoba lalu fallback
    // dari exception spooler bila target memang tidak tersedia.
    return true;
  }
}

bool _printerEksporPdfSistem(String nama) {
  final lower = nama.toLowerCase();
  return lower.contains('pdf') ||
      lower.contains('xps') ||
      lower.contains('onenote');
}

Future<void> cetakPdfDenganDialogOs({
  required pw.Document dokumen,
  required String nama,
}) async {
  await Printing.layoutPdf(onLayout: (_) async => dokumen.save(), name: nama);
}

/// Cetak langsung ke printer default TANPA dialog pilih-printer -- gap-closure:
/// `Printing.layoutPdf` (dipakai semua layar cetak struk sebelumnya) SELALU
/// membuka dialog cetak sistem operasi yang mengharuskan kasir memilih printer
/// tiap kali, walau kasir cuma punya satu printer struk yang sudah jadi default
/// Windows. `Printing.directPrintPdf` butuh objek `Printer` eksplisit (tak ada
/// mode "printer default" bawaan) -- jadi di sini kita `listPrinters()` dulu,
/// cari `isDefault == true`, baru panggil `directPrintPdf` dengannya.
///
/// Kalau printer default tak terdeteksi (mis. belum ada printer terpasang sama
/// sekali), FALLBACK ke `layoutPdf` (dialog cetak biasa) drpd gagal diam --
/// kasir tetap bisa cetak manual sekali itu sambil printer default diatur di
/// Windows.
Future<void> cetakLangsungKePrinterDefault(
    {required pw.Document dokumen, required String nama}) async {
  final printers = await Printing.listPrinters();
  Printer? default_;
  for (final p in printers) {
    if (p.isDefault && p.isAvailable) {
      default_ = p;
      break;
    }
  }
  if (default_ == null) {
    await Printing.layoutPdf(onLayout: (_) async => dokumen.save(), name: nama);
    return;
  }
  final bytes = await dokumen.save();
  await Printing.directPrintPdf(
      printer: default_,
      onLayout: (_) async => Uint8List.fromList(bytes),
      name: nama);
}
