import 'dart:convert';
import 'dart:io';
import 'package:core_db/core_db.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'hasil filter lama hilang saat gagal; cache filter yang sama tetap terbaca',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('laporan-filter-')))!;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    CoreDb.configureStorage('uji_laporan_filter');
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    var offline = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
          home: LaporanDetailScreen(item: {
        'id': 'pnj_per_cabang',
        'judul': 'Uji Laporan',
        'produk': true
      })));
      Future<void> tampil() async {
        await tester.runAsync(() async {
          await tester.tap(find.text('Tampilkan'));
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await tester.pumpAndSettle();
      }

      await tampil();
      expect(find.text('HASIL FILTER AWAL'), findsOneWidget);
      offline = true;
      await tester.enterText(find.byType(TextField).first, 'filter lain');
      await tester.pumpAndSettle();
      expect(find.text('HASIL FILTER AWAL'), findsNothing);
      await tampil();
      expect(find.text('HASIL FILTER AWAL'), findsNothing);
      expect(find.textContaining('belum mempunyai salinan'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tampil();
      expect(find.text('HASIL FILTER AWAL'), findsOneWidget);
      expect(find.textContaining('belum mempunyai salinan'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              if (offline) throw const SocketException('uji offline');
              return http.Response(
                  jsonEncode({
                    'status': 'success',
                    'kolom': [
                      {'l': 'Toko', 't': 'text'}
                    ],
                    'baris': [
                      ['HASIL FILTER AWAL']
                    ]
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
