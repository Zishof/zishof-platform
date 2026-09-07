import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget aplikasi() => const MaterialApp(
        home: AppShell(
          menuAktif: MenuEBisnis.stokOpname,
          judul: 'Stok Opname',
          body: Text('Isi halaman'),
        ),
      );

  testWidgets('desktop hanya menampilkan satu tombol Bantuan mengambang',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(aplikasi());
    await tester.pump();
    expect(find.byKey(const Key('tombol-bantuan-mengambang')), findsOneWidget);
    expect(find.byTooltip('Bantuan halaman ini'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Bantuan'), findsNothing);
    await tester.tap(find.byKey(const Key('tombol-bantuan-mengambang')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bantuan Halaman Ini'));
    await tester.pumpAndSettle();
    expect(find.text('Bantuan Stok Opname'), findsWidgets);
    expect(find.text('Mulai sesi'), findsOneWidget);
  });

  testWidgets('Android/mobile hanya menampilkan satu tombol Bantuan mengambang',
      (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(aplikasi());
    await tester.pump();
    expect(find.byKey(const Key('tombol-bantuan-mengambang')), findsOneWidget);
    expect(find.byTooltip('Bantuan halaman ini'), findsNothing);
  });

  testWidgets('tombol Tanya Jawab membuka QA sesuai halaman', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(aplikasi());
    await tester.pump();
    expect(find.byKey(const Key('tombol-qa-halaman-desktop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tombol-qa-halaman-desktop')));
    await tester.pumpAndSettle();
    expect(find.text('Tanya Jawab — Stok Opname'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsWidgets);
  });

  testWidgets('halaman fokus dapat memakai bantuan header tanpa FAB ganda',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: AppShell(
        menuAktif: MenuEBisnis.kasirApotik,
        judul: 'Kasir Apotik',
        tampilkanBantuanHeader: false,
        tampilkanBantuanMengambang: false,
        tampilkanDropdownGrup: false,
        aksiHeader: TextButton(onPressed: null, child: Text('Bantuan Kasir')),
        body: Text('Isi kasir'),
      ),
    ));
    await tester.pump();

    expect(find.text('Bantuan Kasir'), findsOneWidget);
    expect(find.byKey(const Key('tombol-bantuan-mengambang')), findsNothing);
    expect(find.byKey(const Key('tombol-qa-halaman-desktop')), findsNothing);
    expect(find.byKey(const Key('dropdown-grup-menu')), findsNothing);
  });

  testWidgets('sidebar desktop dapat diringkas dan dibuka kembali',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Tutup menu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tombol-sidebar-ringkas')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Buka menu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tombol-sidebar-ringkas')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tutup menu'), findsOneWidget);
  });
}
