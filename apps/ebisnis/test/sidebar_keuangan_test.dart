import 'dart:io';

import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grup "Keuangan": enam modul alur kas (padanan layar ZK akunting) plus Bayar
/// Pajak & Pembayaran Vendor yang dipindah ke sini dari grup Pengadaan.
void main() {
  Widget aplikasi() => const MaterialApp(
        home: AppShell(
          menuAktif: MenuEBisnis.stokOpname,
          judul: 'Stok Opname',
          body: Text('Isi halaman'),
        ),
      );

  Future<void> pakaiDesktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> bukaGrup(WidgetTester tester, String label) async {
    final daftar = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(label), 200, scrollable: daftar);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  const kunciKeuangan = [
    'uang_muka',
    'pj_uang_muka',
    'kas_besar',
    'pj_kas_besar',
    'kas_kecil',
    'penggantian_kas_kecil',
  ];

  tearDown(() => Sesi.instance.aksesMenu = {});

  testWidgets('enam modul baru fail-closed tanpa kuncinya', (tester) async {
    await pakaiDesktop(tester);
    Sesi.instance.aksesMenu = {};
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    // Grupnya sendiri boleh tampil karena Bayar Pajak & Pembayaran Vendor memakai
    // gerbang lamanya (default boleh) -- yang WAJIB tersembunyi adalah enam modul
    // pencairan dana yang kuncinya belum diberikan admin.
    for (final label in [
      'Uang Muka (Cash Advance)',
      'Pertanggungjawaban Uang Muka',
      'Kas Besar',
      'Pertanggungjawaban Kas Besar',
      'Kas Kecil',
      'Penggantian Kas Kecil (Reimbursement)',
    ]) {
      expect(find.text(label), findsNothing, reason: '$label fail-closed');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('enam modul alur kas muncul setelah kuncinya diberikan',
      (tester) async {
    await pakaiDesktop(tester);
    Sesi.instance.aksesMenu = {for (final k in kunciKeuangan) k: true};
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    await bukaGrup(tester, 'KEUANGAN');

    for (final label in [
      'Uang Muka (Cash Advance)',
      'Pertanggungjawaban Uang Muka',
      'Kas Besar',
      'Pertanggungjawaban Kas Besar',
      'Kas Kecil',
      'Penggantian Kas Kecil (Reimbursement)',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget, reason: 'submenu $label');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bayar Pajak & Pembayaran Vendor pindah ke grup Keuangan',
      (tester) async {
    await pakaiDesktop(tester);
    // Kunci menunya sengaja TIDAK berubah supaya hak akses peran yang sudah
    // diatur tetap berlaku, hanya letak grupnya yang pindah.
    Sesi.instance.aksesMenu = {
      'pengadaan_pajak': true,
      'pengadaan_dpc': true,
      'pengadaan_pr': true,
    };
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    await bukaGrup(tester, 'KEUANGAN');
    for (final label in ['Bayar Pajak', 'Pembayaran Vendor']) {
      await tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  test('grup Pengadaan tidak lagi memuat kedua menu itu', () {
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    final pengadaan = shell.substring(
        shell.indexOf("_GrupMenuShell(\n    'Pengadaan'"),
        shell.indexOf("'Keuangan'"));
    expect(pengadaan, isNot(contains('pengadaanDpc')));
    expect(pengadaan, isNot(contains('pengadaanPajak')));
  });

  test('keenam kunci menu digerbangi fail-closed di kedua platform', () {
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    for (final k in kunciKeuangan) {
      expect(shell, contains("'$k'"), reason: 'sidebar $k');
      expect(drawer, contains("bolehMenuVarianBaru('$k')"), reason: 'drawer $k');
    }
  });
}
