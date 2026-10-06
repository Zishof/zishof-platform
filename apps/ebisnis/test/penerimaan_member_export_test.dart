import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ebisnis/screens/laporan_transaksi_screen.dart';
import 'package:ebisnis/services/dynamic_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _SavePicker extends FilePicker {
  _SavePicker(this.path);
  final String path;
  @override
  Future<String?> saveFile(
          {String? dialogTitle,
          String? fileName,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Uint8List? bytes,
          bool lockParentWindow = false}) async =>
      path;
}

void main() {
  test('rincian member mempertahankan identitas dan porsi split', () {
    final data = buatLaporanRincianPenerimaan({
      'tanggal': '2026-10-02',
      'kasir': 'Kasir Uji',
      'metode': 'Tunai',
    }, [
      {
        'nomorNota': 'UJI-1',
        'pembeli': '000123 Member Uji',
        'totalBiaya': 35000,
        'bayarTunai': 15000,
        'qty': 2,
        'metode': 'QRIS Rp 20.000 + Tunai Rp 15.000',
      },
      {
        'nomorNota': 'UJI-2',
        'pembeli': 'Umum',
        'totalBiaya': 5000,
        'metode': 'Tunai',
      }
    ]);
    expect(data.rows.length, 2);
    expect(data.rows.first['pembeli'], '000123 Member Uji');
    expect(data.rows.first['totalNota'], 35000);
    expect(data.rows.first['penerimaanMetode'], 15000);
    final totals = DynamicReportDesigner.totals(
        data, DynamicReportModel.fromData(data), data.rows);
    expect(totals['penerimaanMetode'], 20000);
    expect(data.subtitle, contains('20.000'));
  });

  testWidgets('dialog mengambil halaman lanjut dan menyediakan PDF/Excel',
      (tester) async {
    final pages = <int>[];
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(() async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
            onPressed: () => lihatRincianPenerimaan(context, {
                  'tanggal': '2026-10-02',
                  'kasir': 'Kasir Uji',
                  'metode': 'Tunai',
                  'jumlahTransaksi': 101,
                  'total': 101000,
                }),
            child: const Text('Buka rincian'));
      }))));
      await tester.runAsync(() async {
        await tester.tap(find.text('Buka rincian'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(pages, [1, 2]);
      expect(
          find.byKey(const ValueKey('rincian-penerimaan-pdf')), findsOneWidget);
      expect(find.byKey(const ValueKey('rincian-penerimaan-excel')),
          findsOneWidget);
      expect(find.text('Metode / bank: Tunai'), findsOneWidget);
      final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('rincian-member-uji-')))!;
      FilePicker.platform = _SavePicker('${dir.path}/rincian.xlsx');
      await tester.runAsync(() async {
        await tester
            .tap(find.byKey(const ValueKey('rincian-penerimaan-excel')));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      final bytes = await tester
          .runAsync(() => File('${dir.path}/rincian.xlsx').readAsBytes());
      final zip = ZipDecoder().decodeBytes(bytes!);
      final sheet = utf8.decode(
          zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
      expect(sheet, contains('UJI-100'));
      expect(sheet, contains('Member Uji 99'));
      expect(sheet, contains('101000'));
      await tester.runAsync(() => dir.delete(recursive: true));

      const channel = MethodChannel('net.nfet.printing');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Uint8List? pdfBytes;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'printPdf') {
          final args = call.arguments as Map;
          expect(args['width'], greaterThan(args['height']));
          for (final event in [
            MethodCall('onLayout', {
              'job': args['job'],
              'width': args['width'],
              'height': args['height'],
              'marginLeft': 0.0,
              'marginRight': 0.0,
              'marginTop': 0.0,
              'marginBottom': 0.0
            }),
            MethodCall('onCompleted', {'job': args['job'], 'completed': true}),
          ]) {
            await messenger.handlePlatformMessage(channel.name,
                const StandardMethodCodec().encodeMethodCall(event), (reply) {
              if (event.method == 'onLayout') {
                pdfBytes = const StandardMethodCodec().decodeEnvelope(reply!)
                    as Uint8List;
              }
            });
          }
          return 1;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('rincian-penerimaan-pdf')));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(ascii.decode(pdfBytes!.take(4).toList()), '%PDF');
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              final payload = jsonDecode(request.body) as Map<String, dynamic>;
              final page = (payload['page'] as num).toInt();
              pages.add(page);
              expect(payload['action'], 'laporan_penerimaan_kasir_detail');
              expect(payload['metode'], 'Tunai');
              expect(payload['kasir'], 'Kasir Uji');
              return http.Response(
                  jsonEncode({
                    'status': 'success',
                    'total': 101,
                    'data': List.generate(
                        page == 1 ? 100 : 1,
                        (i) => {
                              'nomorNota': 'UJI-${(page - 1) * 100 + i}',
                              'pembeli': 'Member Uji $i',
                              'totalBiaya': 1000,
                            }),
                  }),
                  200,
                  headers: {'content-type': 'application/json'});
            }));
  });
}
