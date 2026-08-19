import 'package:ebisnis/widgets/app_components.dart';
import 'package:ebisnis/widgets/app_drawer.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void pakaiUkuranPonsel(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('aksi header yang banyak masuk menu overflow di ponsel',
      (tester) async {
    pakaiUkuranPonsel(tester);
    var dipilih = '';
    final actions = [
      for (final label in ['Ekspor', 'Impor', 'Cetak PDF', 'Muat Ulang'])
        HeaderActionButton(
          icon: Icons.settings,
          label: label,
          onPressed: () => dipilih = label,
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        menuAktif: MenuEBisnis.produk,
        judul: 'Manajemen Produk',
        actionsAppBar: actions,
        body: const Text('Isi'),
      ),
    ));
    await tester.pump();

    expect(find.text('Manajemen Produk'), findsOneWidget);
    expect(find.byKey(const Key('menu-aksi-halaman-mobile')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('menu-aksi-halaman-mobile')));
    await tester.pumpAndSettle();
    expect(find.text('Ekspor'), findsOneWidget);
    expect(find.text('Muat Ulang'), findsOneWidget);
    await tester.tap(find.text('Muat Ulang'));
    await tester.pumpAndSettle();
    expect(dipilih, 'Muat Ulang');
  });

  testWidgets('drawer dapat digulir dan memuat seluruh menu mobile baru',
      (tester) async {
    pakaiUkuranPonsel(tester);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppDrawer()),
    ));
    await tester.pump();

    expect(find.byType(Scrollbar), findsOneWidget);
    final daftar = find.byType(Scrollable).first;
    for (final label in [
      'Jenis Produk',
      'Kedaluwarsa',
      'Mutasi Antar Outlet',
      'Cara Pembayaran',
      // Menu keuangan kini berupa grup 'Akuntansi' yang bawaannya tertutup.
      'Akuntansi',
      'Konfigurasi',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        260,
        scrollable: daftar,
      );
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
