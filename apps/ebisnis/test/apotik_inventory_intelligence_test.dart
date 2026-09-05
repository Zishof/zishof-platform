import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_inventory_intelligence_page.dart';
import 'package:ebisnis/features/apotik/core/apotik_lokal_dulu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MuatDaftarApotik _pemuat() {
  return (aksi, body, cacheKey, {required onData}) async {
    if (aksi == 'apotik_batch_monitor') {
      onData({
        'data': [
          {
            'kadaluarsaId': 1,
            'nama': 'Insulin Cold Chain',
            'kode': 'INS-01',
            'tanggalKadaluarsa': '2027-10-01',
            'sisa': 25,
            'statusLot': 'RECALL',
            'lotLayak': false,
            'alasanLot': 'Recall principal',
            'coldChain': true,
            'lokasiNama': 'Kulkas Farmasi',
          },
          {
            'kadaluarsaId': 2,
            'nama': 'Paracetamol',
            'kode': 'PCT-01',
            'tanggalKadaluarsa': '2028-01-01',
            'sisa': 50,
            'statusLot': 'ELIGIBLE',
            'lotLayak': true,
            'coldChain': false,
            'lokasiNama': 'Rak OTC',
          },
        ],
        'dariServer': true,
      });
    } else {
      onData({
        'data': [
          {
            'id': 1,
            'nama': 'Stok Rendah',
            'kode': 'LOW-01',
            'stok': 3,
            'satuan': 'Tablet'
          },
          {
            'id': 2,
            'nama': 'Stok Aman',
            'kode': 'OK-01',
            'stok': 40,
            'satuan': 'Botol'
          },
        ],
        'dariServer': true,
      });
    }
  };
}

Future<void> _pump(WidgetTester tester, {int tabAwal = 0}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: Scaffold(
        body: ApotikInventoryIntelligencePage(
            tabAwal: tabAwal, muatDaftar: _pemuat())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recall menampilkan status lot dan alasan aktual',
      (tester) async {
    await _pump(tester);
    expect(find.text('Insulin Cold Chain'), findsOneWidget);
    expect(find.text('Recall principal'), findsOneWidget);
    expect(find.textContaining('Ditahan / recall'), findsOneWidget);
  });

  testWidgets('cold chain menampilkan batch dan kendali suhu', (tester) async {
    await _pump(tester, tabAwal: 1);
    expect(find.text('Insulin Cold Chain'), findsOneWidget);
    expect(find.textContaining('Kendali 2–8 °C'), findsOneWidget);
    expect(find.text('Paracetamol'), findsNothing);
  });

  testWidgets('lokasi mengelompokkan batch dan membuka transfer',
      (tester) async {
    var dibuka = false;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
          useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
      home: Scaffold(
          body: ApotikInventoryIntelligencePage(
        tabAwal: 2,
        muatDaftar: _pemuat(),
        bukaTransfer: () => dibuka = true,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Kulkas Farmasi'), findsOneWidget);
    expect(find.text('Rak OTC'), findsOneWidget);
    await tester.tap(find.text('Buat Transfer Antar Lokasi'));
    expect(dibuka, true);
  });

  testWidgets('perencanaan mengurutkan stok terendah', (tester) async {
    await _pump(tester, tabAwal: 3);
    expect(find.text('Stok Rendah'), findsOneWidget);
    expect(find.text('Stok 3'), findsOneWidget);
    final rendah = tester.getTopLeft(find.text('Stok Rendah')).dy;
    final aman = tester.getTopLeft(find.text('Stok Aman')).dy;
    expect(rendah, lessThan(aman));
  });
}
