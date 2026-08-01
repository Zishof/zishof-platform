import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Buka Laci Kasir (cash drawer) -- Windows-only, padanan PERSIS mekanisme
/// `buatSkripBukaLaci`/`pos:buka-laci-kasir` di `main.js` desktop-pos-electron:
/// laci TIDAK punya kabel/driver sendiri, ia nyambung lewat port RJ11 ke
/// printer struk thermal, jadi "membuka laci" = mengirim byte ESC/POS pulsa
/// (`1B 70 00 19 FA` utk pin 2, `1B 70 01 19 FA` utk pin 5) sbg data RAW ke
/// PRINTER DEFAULT Windows saat ini -- persis spooler yg sama dipakai cetak
/// struk, lewat winspool.drv (`OpenPrinter`/`StartDocPrinter`/`WritePrinter`,
/// pola RawPrinterHelper KB322091), BUKAN library node/plugin pihak ketiga.
///
/// Referensi Electron TIDAK punya pengaturan nama printer/COM-port sendiri
/// (selalu ikut default printer OS) -- disengaja disamakan di sini supaya
/// perilaku identik: pengguna atur printer default lewat Windows Settings.
///
/// Melempar [Exception] berisi pesan Indonesia bila printer default tak ada
/// atau spooler menolak (mis. driver bermasalah) -- pemanggil (UI) yang
/// memutuskan cara menampilkannya (SnackBar/dialog), fungsi ini tak pernah
/// menampilkan apa pun sendiri.
Future<void> bukaLaciKasir({bool pinAlternatif = false}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    throw Exception('Buka Laci hanya didukung di Windows.');
  }

  final namaPrinter = _namaPrinterDefault();
  if (namaPrinter == null || namaPrinter.isEmpty) {
    throw Exception('Tidak ada printer default yang terpasang di Windows. Atur printer default lalu coba lagi.');
  }

  final bytes = Uint8List.fromList(
    pinAlternatif ? [0x1B, 0x70, 0x01, 0x19, 0xFA] : [0x1B, 0x70, 0x00, 0x19, 0xFA],
  );
  _tulisRawKePrinter(namaPrinter, bytes, 'Buka Laci Kasir');
}

String? _namaPrinterDefault() {
  final pcchBuffer = calloc<Uint32>();
  try {
    GetDefaultPrinter(nullptr, pcchBuffer);
    final ukuran = pcchBuffer.value;
    if (ukuran == 0) return null;
    final buffer = calloc<Uint16>(ukuran);
    try {
      final ok = GetDefaultPrinter(buffer.cast<Utf16>(), pcchBuffer);
      if (ok == 0) return null;
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(pcchBuffer);
  }
}

/// Kirim [bytes] sbg dokumen RAW ke printer [namaPrinter] -- dipakai ulang
/// dari [bukaLaciKasir] (dan bisa dipakai jalur cetak struk ESC/POS nanti
/// bila diperlukan, tanpa duplikasi boilerplate winspool ini).
void _tulisRawKePrinter(String namaPrinter, Uint8List bytes, String namaDokumen) {
  final phPrinter = calloc<IntPtr>();
  final printerNamePtr = namaPrinter.toNativeUtf16();
  try {
    if (OpenPrinter(printerNamePtr, phPrinter, nullptr) == 0) {
      throw Exception('Gagal membuka printer "$namaPrinter" (kode ${GetLastError()}).');
    }
    final hPrinter = phPrinter.value;
    final docInfo = calloc<DOC_INFO_1>();
    final docNamePtr = namaDokumen.toNativeUtf16();
    final dataTypePtr = 'RAW'.toNativeUtf16();
    try {
      docInfo.ref.pDocName = docNamePtr;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype = dataTypePtr;

      final jobId = StartDocPrinter(hPrinter, 1, docInfo);
      if (jobId == 0) {
        throw Exception('Gagal memulai dokumen cetak (kode ${GetLastError()}).');
      }
      try {
        if (StartPagePrinter(hPrinter) == 0) {
          throw Exception('Gagal memulai halaman cetak (kode ${GetLastError()}).');
        }
        try {
          final buf = calloc<Uint8>(bytes.length);
          final pcWritten = calloc<Uint32>();
          try {
            buf.asTypedList(bytes.length).setAll(0, bytes);
            if (WritePrinter(hPrinter, buf.cast(), bytes.length, pcWritten) == 0) {
              throw Exception('Gagal menulis ke printer (kode ${GetLastError()}).');
            }
          } finally {
            calloc.free(buf);
            calloc.free(pcWritten);
          }
        } finally {
          EndPagePrinter(hPrinter);
        }
      } finally {
        EndDocPrinter(hPrinter);
      }
    } finally {
      calloc.free(docInfo);
      calloc.free(docNamePtr);
      calloc.free(dataTypePtr);
    }
    ClosePrinter(hPrinter);
  } finally {
    calloc.free(phPrinter);
    calloc.free(printerNamePtr);
  }
}
