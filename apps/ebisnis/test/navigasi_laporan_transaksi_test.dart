import 'package:ebisnis/widgets/navigasi_laporan_transaksi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class LaporanUji extends StatefulWidget {
  const LaporanUji({super.key});
  @override
  State<LaporanUji> createState() => _LaporanUjiState();
}

class _LaporanUjiState extends State<LaporanUji>
    with SingleTickerProviderStateMixin {
  late final TabController controller;
  @override
  void initState() {
    super.initState();
    controller = TabController(
        length: NavigasiLaporanTransaksi.jenisLaporan.length, vsync: this);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
          home: Scaffold(
              body: Column(children: [
        NavigasiLaporanTransaksi(controller: controller),
        Expanded(
            child: TabBarView(controller: controller, children: [
          for (var i = 0; i < NavigasiLaporanTransaksi.jenisLaporan.length; i++)
            Center(child: Text('Isi laporan $i')),
        ])),
      ])));
}

void main() {
  for (final width in [360.0, 1024.0, 1280.0]) {
    testWidgets(
        'Rincian Produk dapat dibuka pada lebar $width tanpa menggeser tab',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const LaporanUji());
      final pemilih = find.byKey(const Key('pemilih-jenis-laporan-transaksi'));
      expect(pemilih, findsOneWidget);
      final field = tester.widget<DropdownButton<int>>(find.descendant(
          of: pemilih, matching: find.byType(DropdownButton<int>)));
      expect(field.items!.map((e) => e.value),
          orderedEquals([0, 1, 2, 3, 4, 5, 6]));
      await tester.tap(pemilih);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rincian Produk').last);
      await tester.pumpAndSettle();
      expect(find.text('Isi laporan 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Rotasi/perubahan ukuran mempertahankan laporan serta indeks ekspor.
      tester.view.physicalSize = const Size(1700, 800);
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 6);
      expect(find.text('Isi laporan 6'), findsOneWidget);
    });
  }
  testWidgets('tab desktop lebar tetap mempunyai tujuh laporan',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1700, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LaporanUji());
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.tabs.length, 7);
    await tester.tap(find.text('Rincian Produk'));
    await tester.pumpAndSettle();
    expect(find.text('Isi laporan 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
