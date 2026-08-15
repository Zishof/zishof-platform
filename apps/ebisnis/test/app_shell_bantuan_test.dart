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

  testWidgets('desktop menampilkan tombol Bantuan kontekstual', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(aplikasi());
    await tester.pump();
    expect(find.text('Bantuan'), findsOneWidget);
    await tester.tap(find.text('Bantuan'));
    await tester.pumpAndSettle();
    expect(find.text('Bantuan Stok Opname'), findsWidgets);
    expect(find.text('Mulai sesi'), findsOneWidget);
  });

  testWidgets('Android/mobile menampilkan ikon Bantuan di AppBar',
      (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(aplikasi());
    await tester.pump();
    expect(find.byTooltip('Bantuan halaman ini'), findsOneWidget);
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
}
