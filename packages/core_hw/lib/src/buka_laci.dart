import 'dart:ffi';

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
/// [namaPrinter] -- OPSIONAL, gap-closure: laci fisik BELUM TENTU nyambung ke
/// printer yang kebetulan jadi "default" Windows (mis. toko punya >1 printer,
/// atau default-nya "Microsoft Print to PDF") -- laporan lapangan "Buka Laci
/// tidak berfungsi" seringkali sebenarnya salah target printer, bukan salah
/// perintah ESC/POS-nya. Kalau `null`/kosong, tetap fallback ke printer
/// default Windows spt semula (perilaku lama TIDAK berubah kalau pengguna
/// belum pernah mengatur printer laci secara eksplisit).
/// ===================================================================
/// CATATAN PENTING: ADA DUA PEMANGGIL, KEDUANYA DISENGAJA
/// ===================================================================
///
/// 1. Tombol "Buka Laci" di layar Kasir dan layar Struk -- pembukaan manual.
/// 2. `StrukScreen._cetakStruk` -- pembukaan OTOMATIS setiap kali struk
///    transaksi baru dicetak.
///
/// Pemanggil kedua ditambahkan setelah laporan kasir 21-08-2026: "cetak
/// struk tidak membuka laci, biasanya otomatis". Penyebabnya aliran ESC/POS
/// struk TIDAK pernah memuat pulsa buka laci, sehingga laci hanya terbuka
/// lewat tombol -- tombol tesnya berfungsi, cetak struknya tidak, dan itu
/// membingungkan karena tampak seperti kerusakan perangkat keras.
///
/// JANGAN memindahkan pulsa ini ke dalam `_strukEscPos`. Aliran struk dibaca
/// juga oleh jalur pratinjau dan cetak ulang; menaruh pulsanya di sana
/// membuat laci terbuka pada cetak ulang struk lama, dan itu celah kontrol
/// kas -- siapa pun bisa membuka laci lewat menu riwayat.
Future<void> bukaLaciKasir(
    {bool pinAlternatif = false, String? namaPrinter}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    throw Exception('Buka Laci hanya didukung di Windows.');
  }

  final target = (namaPrinter != null && namaPrinter.trim().isNotEmpty)
      ? namaPrinter.trim()
      : _namaPrinterDefault();
  if (target == null || target.isEmpty) {
    throw Exception(
        'Tidak ada printer default yang terpasang di Windows. Atur printer default lalu coba lagi.');
  }

  final bytes = Uint8List.fromList(
    pinAlternatif
        ? [0x1B, 0x70, 0x01, 0x19, 0xFA]
        : [0x1B, 0x70, 0x00, 0x19, 0xFA],
  );
  _tulisRawKePrinter(target, bytes, 'Buka Laci Kasir');
}

/// Mengirim satu dokumen RAW langsung ke spooler Windows. Jalur ini ditujukan
/// untuk printer thermal ESC/POS agar driver tidak mengubah struk roll menjadi
/// halaman A4. Seluruh [bytes] ditulis dalam satu job; pemanggil wajib menaruh
/// perintah feed/cut hanya setelah isi struk selesai.
Future<void> cetakRawKasir(
  Uint8List bytes, {
  String? namaPrinter,
  String namaDokumen = 'Struk POS',
}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    throw Exception('Cetak RAW hanya didukung di Windows.');
  }
  if (bytes.isEmpty) throw Exception('Data struk kosong.');
  final target = (namaPrinter != null && namaPrinter.trim().isNotEmpty)
      ? namaPrinter.trim()
      : _namaPrinterDefault();
  if (target == null || target.isEmpty) {
    throw Exception(
        'Tidak ada printer default yang terpasang di Windows. Atur printer default lalu coba lagi.');
  }
  _tulisRawKePrinter(target, bytes, namaDokumen);
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
void _tulisRawKePrinter(
    String namaPrinter, Uint8List bytes, String namaDokumen) {
  final phPrinter = calloc<IntPtr>();
  final printerNamePtr = namaPrinter.toNativeUtf16();
  var hPrinter = 0;
  try {
    if (OpenPrinter(printerNamePtr, phPrinter, nullptr) == 0) {
      throw Exception(
          'Gagal membuka printer "$namaPrinter" (kode ${GetLastError()}).');
    }
    hPrinter = phPrinter.value;
    final docInfo = calloc<DOC_INFO_1>();
    final docNamePtr = namaDokumen.toNativeUtf16();
    final dataTypePtr = 'RAW'.toNativeUtf16();
    try {
      docInfo.ref.pDocName = docNamePtr;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype = dataTypePtr;

      final jobId = StartDocPrinter(hPrinter, 1, docInfo);
      if (jobId == 0) {
        throw Exception(
            'Gagal memulai dokumen cetak (kode ${GetLastError()}).');
      }
      try {
        if (StartPagePrinter(hPrinter) == 0) {
          throw Exception(
              'Gagal memulai halaman cetak (kode ${GetLastError()}).');
        }
        try {
          final buf = calloc<Uint8>(bytes.length);
          final pcWritten = calloc<Uint32>();
          try {
            buf.asTypedList(bytes.length).setAll(0, bytes);
            var offset = 0;
            while (offset < bytes.length) {
              // Sebagian driver/spooler hanya menerima sebagian buffer besar.
              // Teruskan dari byte terakhir yang benar-benar diterima agar
              // bagian akhir struk (total, footer, dan CUT) tidak hilang.
              final remaining = bytes.length - offset;
              final chunk = remaining > 16384 ? 16384 : remaining;
              pcWritten.value = 0;
              if (WritePrinter(
                      hPrinter, (buf + offset).cast(), chunk, pcWritten) ==
                  0) {
                throw Exception(
                    'Gagal menulis ke printer (kode ${GetLastError()}).');
              }
              if (pcWritten.value == 0) {
                throw Exception(
                    'Printer tidak menerima lanjutan data struk pada byte $offset.');
              }
              offset += pcWritten.value;
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
  } finally {
    if (hPrinter != 0) ClosePrinter(hPrinter);
    calloc.free(phPrinter);
    calloc.free(printerNamePtr);
  }
}
