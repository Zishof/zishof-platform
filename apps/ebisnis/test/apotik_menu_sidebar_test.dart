import 'package:ebisnis/product_profile.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/widgets/app_drawer.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppProductProfile profilSebelumnya;

  setUp(() {
    profilSebelumnya = AppProductProfile.aktif;
    AppProductProfile.aktif = const AppProductProfile.apotik();
    Sesi.instance.reset();
  });

  tearDown(() {
    AppProductProfile.aktif = profilSebelumnya;
    Sesi.instance.reset();
  });

  test('seluruh fungsi dan pengembangan Apotik punya menu aktif', () {
    final menu = ringkasanMenuApotikSidebar();

    expect(menu.map((e) => e.label), [
      'Dashboard Apotik',
      'Kasir Apotik',
      'Tebus Resep Dokter',
      'Racikan',
      'Produksi Farmasi',
      'Manajemen Farmasi',
      'Formularium & Obat',
      'Batch & Kedaluwarsa',
      'Pengadaan / PBF',
      'Stok Opname Apotik',
      'Retur Obat',
      'Obat Terkendali',
      'Laporan Apotik',
    ]);
    expect(menu.first.kunciServer, isNull,
        reason: 'dashboard adalah pintu diagnostik varian');
    expect(
        menu
            .where((e) => e.kunciServer != null)
            .map((e) => e.kunciServer)
            .toSet(),
        {
          'apotik_kasir',
          'apotik_resep',
          'apotik_racikan',
          'apotik_formularium',
          'apotik_batch',
          'apotik_pengadaan',
          'apotik_stok_opname',
          'apotik_retur',
          'apotik_narkotika',
          'apotik_laporan',
        });
    expect(
      menu.firstWhere((e) => e.label == 'Manajemen Farmasi').kunciServer,
      isNull,
      reason: 'hub boleh dibuka oleh pemilik hak Apotik mana pun',
    );
    expect(menu.every((e) => e.punyaTujuan), isTrue);
  });

  test('hak Apotik diterapkan fail-closed pada menu operasional', () {
    final menu = ringkasanMenuApotikSidebar();
    final operasional = menu
        .where((e) => e.kunciServer != null)
        .where((e) => e.label != 'Produksi Farmasi')
        .toList();
    for (final dipilih in operasional) {
      Sesi.instance.aksesMenu = {dipilih.kunciServer!: true};
      for (final diperiksa in operasional) {
        expect(
          bolehTampilMenu(diperiksa.menu),
          diperiksa.menu == dipilih.menu,
          reason:
              '${dipilih.kunciServer} tidak boleh ikut membuka ${diperiksa.kunciServer}',
        );
      }
      expect(bolehTampilMenu(MenuEBisnis.manajemenFarmasiApotik), isTrue);
    }
    Sesi.instance.aksesMenu = const {};
    expect(bolehTampilMenu(MenuEBisnis.manajemenFarmasiApotik), isFalse);
  });

  test('produksi mengikuti hak racikan tanpa membuka menu lain', () {
    Sesi.instance.aksesMenu = const {'apotik_racikan': true};
    expect(bolehTampilMenu(MenuEBisnis.racikanApotik), isTrue);
    expect(bolehTampilMenu(MenuEBisnis.produksiFarmasiApotik), isTrue);
    expect(bolehTampilMenu(MenuEBisnis.kasirApotik), isFalse);
  });

  testWidgets('sidebar desktop menampilkan seluruh menu Apotik yang diizinkan',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Sesi.instance.aksesMenu = {
      for (final item in ringkasanMenuApotikSidebar()
          .where((item) => item.kunciServer != null))
        item.kunciServer!: true,
    };

    await tester.pumpWidget(const MaterialApp(
      home: AppShell(
        menuAktif: MenuEBisnis.berandaApotik,
        judul: 'Uji Menu Apotik',
        body: Text('Isi'),
      ),
    ));
    await tester.pump();

    for (final item in ringkasanMenuApotikSidebar()) {
      expect(find.text(item.label), findsWidgets, reason: item.label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer mobile menampilkan seluruh menu Apotik yang diizinkan',
      (tester) async {
    tester.view.physicalSize = const Size(412, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Sesi.instance.aksesMenu = {
      for (final item in ringkasanMenuApotikSidebar()
          .where((item) => item.kunciServer != null))
        item.kunciServer!: true,
    };
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppDrawer(menuAktif: 'Dashboard Apotik')),
    ));
    await tester.pump();

    final daftar = find.byType(Scrollable).first;
    for (final item in ringkasanMenuApotikSidebar()) {
      if (find.text(item.label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.text(item.label), 180,
            scrollable: daftar);
      }
      expect(find.text(item.label), findsOneWidget, reason: item.label);
    }
    expect(tester.takeException(), isNull);
  });
}
