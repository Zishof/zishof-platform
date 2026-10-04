import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:core_db/core_db.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Excel mempertahankan kop, periode, ID teks dan BPP yang belum tersedia',
      () {
    final bytes = buildLaporanDetailXlsx([
      {'l': 'ID Pelanggan', 't': 'text'},
      {'l': 'BPP', 't': 'num'},
    ], [
      ['000123', null]
    ],
        kopNama: 'Ekonomi & Syariah',
        judul: 'Penjualan',
        periode: 'Oktober 2026');
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(xml, contains('Ekonomi &amp; Syariah'));
    expect(xml, contains('Oktober 2026'));
    expect(xml, contains('r="A5" t="inlineStr"'));
    expect(xml, contains('000123'));
    expect(xml, isNot(contains('r="B5"')));
  });

  for (final spec in [
    ['pnj_per_cabang', 'Harian: Penjualan, BPP, Laba', 'harian'],
    ['pnj_per_pemasok', 'Ringkasan global per pemasok', 'global'],
    ['pnj_per_kategori_pelanggan', 'Rincian setiap member', 'member'],
  ]) {
    testWidgets(
        'filter ${spec[2]} mengganti hasil lama dan menolak respons server lama',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('laporan-tambahan-')))!;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      CoreDb.configureStorage('uji_laporan_tambahan_${spec[2]}');
      await tester.runAsync(() async {
        await CoreDb.instance.db;
      });
      addTearDown(() async {
        await tester.runAsync(() => CoreDb.instance.tutup());
      });
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      var didukung = false;
      final payloads = <Map<String, dynamic>>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
            home: LaporanDetailScreen(item: {
          'id': spec[0],
          'judul': 'Uji Laporan'
        }, hasilAwal: const {
          'kolom': [
            {'l': 'Nilai', 't': 'text'}
          ],
          'baris': [
            ['HASIL LAMA']
          ]
        })));
        expect(find.text('HASIL LAMA'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('mode-laporan-tambahan')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(spec[1]).last);
        await tester.pumpAndSettle();
        expect(find.text('HASIL LAMA'), findsNothing);
        await tester.enterText(
            find.byKey(const ValueKey('kop-nama-laporan')), 'Ekonomi Syariah');
        Future<void> tampil() async {
          await tester.runAsync(() async {
            await tester.tap(find.text('Tampilkan'));
            await Future<void>.delayed(const Duration(milliseconds: 800));
          });
          await tester.pumpAndSettle();
        }

        await tampil();
        expect(find.textContaining('Server belum mendukung bentuk/kop'),
            findsOneWidget);
        expect(find.text('HASIL BARU'), findsNothing);
        didukung = true;
        await tampil();
        expect(find.text('HASIL BARU'), findsOneWidget);
        expect(payloads.last['modeLaporan'], spec[2]);
        expect(payloads.last['kopNama'], 'Ekonomi Syariah');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
          () => MockClient((request) async {
                payloads.add(
                    Map<String, dynamic>.from(jsonDecode(request.body) as Map));
                return http.Response(
                    jsonEncode({
                      'status': 'success',
                      if (didukung) 'modeLaporan': spec[2],
                      if (didukung) 'kopKustomDidukung': true,
                      'kolom': [
                        {'l': 'Nilai', 't': 'text'}
                      ],
                      'baris': [
                        ['HASIL BARU']
                      ],
                    }),
                    200);
              }));
      await tester.runAsync(() => CoreDb.instance.tutup());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }
}
