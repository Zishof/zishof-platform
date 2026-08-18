import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/services/master_offline.dart';
import 'package:ebisnis/widgets/indikator_baris_sinkron.dart';

Widget _bungkus(Widget anak) => MaterialApp(home: Scaffold(body: anak));

void main() {
  testWidgets('diam: tidak menggambar ikon apa pun', (tester) async {
    MasterOffline.aturStatusBarisUntukTest('produk:1', null);
    await tester
        .pumpWidget(_bungkus(const IndikatorBarisSinkron(kunci: 'produk:1')));
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('menunggu: awan offline berdenyut tampil', (tester) async {
    MasterOffline.aturStatusBarisUntukTest('produk:2', 'PENDING');
    await tester
        .pumpWidget(_bungkus(const IndikatorBarisSinkron(kunci: 'produk:2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    MasterOffline.aturStatusBarisUntukTest('produk:2', null);
  });

  testWidgets('gagal: ikon galat tampil', (tester) async {
    MasterOffline.aturStatusBarisUntukTest('produk:3', 'GAGAL');
    await tester
        .pumpWidget(_bungkus(const IndikatorBarisSinkron(kunci: 'produk:3')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    MasterOffline.aturStatusBarisUntukTest('produk:3', null);
  });

  testWidgets('baru tersinkron: centang hijau muncul menggantikan awan',
      (tester) async {
    MasterOffline.aturStatusBarisUntukTest('produk:4', 'PENDING');
    await tester
        .pumpWidget(_bungkus(const IndikatorBarisSinkron(kunci: 'produk:4')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);

    // Baris terbukti sampai server -> centang animasi.
    MasterOffline.aturStatusBarisUntukTest('produk:4', null, baruSukses: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    MasterOffline.aturStatusBarisUntukTest('produk:4', null);
    await tester.pump(const Duration(milliseconds: 300));
  });

  test('kunciBarisMaster: pakai _kunci cache bila ada, fallback entitas:id',
      () {
    expect(kunciBarisMaster('produk', {'id': 7}), 'produk:7');
    expect(
        kunciBarisMaster('produk',
            {'id': null, '_kunci': 'produk:baru:123', '_offline': true}),
        'produk:baru:123');
  });
}
