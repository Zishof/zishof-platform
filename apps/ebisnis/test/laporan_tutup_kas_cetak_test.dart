import 'dart:io';

import 'package:ebisnis/services/laporan_tutup_kas_pdf.dart';
import 'package:ebisnis/services/print_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.nfet.printing');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final width in [58.0, 72.0, 76.0, 80.0]) {
    test('format thermal $width diteruskan ke spooler dan fallback', () async {
      final (document, format) = await buatPdfLaporanTutupKas({
        'namaToko': 'Toko Uji',
        'namaKasir': 'Kasir Uji',
        'penjualanTunai': 123456789,
        'selisih': -99999999,
        'metodePembayaran': List.generate(
            12,
            (i) => {
                  'nama': 'Metode pembayaran dengan nama panjang $i',
                  'penerimaan': 123456789,
                  'retur': 1000,
                  'total': 123455789,
                }),
      }, lebarMm: width);
      final bytes = await document.save();
      expect(bytes.length, greaterThan(1000));
      expect(format.width, closeTo(width * PdfPageFormat.mm, 0.01));
      expect(format.height.isFinite, true);
      final evidence = Platform.environment['CASH_PDF_EVIDENCE'];
      if (evidence != null) {
        await Directory(evidence).create(recursive: true);
        await File('$evidence/tutup-kas-${width.toInt()}mm.pdf')
            .writeAsBytes(bytes);
      }
      for (final defaultPrinter in [true, false]) {
        Map<dynamic, dynamic>? sent;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'listPrinters') {
            return defaultPrinter
                ? [
                    {
                      'url': 'uji-thermal',
                      'name': 'Uji Thermal',
                      'default': true,
                      'available': true,
                    }
                  ]
                : [];
          }
          if (call.method == 'printPdf') {
            sent = call.arguments as Map;
            await messenger.handlePlatformMessage(
                channel.name,
                const StandardMethodCodec()
                    .encodeMethodCall(MethodCall('onCompleted', {
                  'job': sent!['job'],
                  'completed': true,
                })),
                (_) {});
            return 1;
          }
          return null;
        });
        await cetakLangsungKePrinterDefault(
            dokumen: document, nama: 'Uji Tutup Kas', format: format);
        expect(sent!['width'], closeTo(width * PdfPageFormat.mm, 0.01));
        expect(sent!['height'], format.height);
        expect(sent!['dynamic'], false);
        expect(sent!['printer'], defaultPrinter ? 'uji-thermal' : null);
      }
      messenger.setMockMethodCallHandler(channel, null);
    });
  }
}
