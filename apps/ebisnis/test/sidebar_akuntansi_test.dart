import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sidebar Desktop: tab-tab layar Laporan Keuangan kini menjadi submenu grup
/// "Akuntansi", susunannya sama dengan drawer Android (lihat
/// mobile_navigation_layout_test.dart untuk sisi Android).
void main() {
  Widget aplikasi() => const MaterialApp(
        home: AppShell(
          menuAktif: MenuEBisnis.stokOpname,
          judul: 'Stok Opname',
          body: Text('Isi halaman'),
        ),
      );

  Future<void> pakaiDesktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> bukaGrup(WidgetTester tester) async {
    final daftar = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('AKUNTANSI'), 200,
        scrollable: daftar);
    await tester.tap(find.text('AKUNTANSI'));
    await tester.pumpAndSettle();
  }

  tearDown(() => Sesi.instance.aksesMenu = {});

  testWidgets('grup AKUNTANSI menggantikan item tunggal "Laporan Keuangan"',
      (tester) async {
    await pakaiDesktop(tester);
    Sesi.instance.aksesMenu = {};
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();

    expect(find.text('AKUNTANSI'), findsOneWidget);
    expect(find.text('Laporan Keuangan'), findsNothing,
        reason: 'menu lama sudah berubah jadi grup "Akuntansi"');
    expect(tester.takeException(), isNull);
  });

  testWidgets('submenu bekas tab punya kunci menunya sendiri', (tester) async {
    await pakaiDesktop(tester);
    // Keenamnya terdaftar di EbisnisMenuKatalog sehingga admin bisa mengatur satu
    // per satu; tanpa kuncinya, submenu tidak boleh muncul (fail-closed).
    Sesi.instance.aksesMenu = {
      'laporankeuangan': true,
      'saldo_awal_akun': true,
      'jurnal_penyesuaian': true,
      'tutup_buku': true,
      'posting_kulakan': true,
      'posting_bayar_hutang': true,
      'posting_terima_piutang': true,
    };
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    await bukaGrup(tester);

    for (final label in [
      'Katalog Laporan',
      'Saldo Awal (Neraca Awal)',
      'Jurnal Penyesuaian Berkala',
      'Tutup Buku (Laba Ditahan)',
      'Posting Kulakan',
      'Posting Bayar Hutang',
      'Posting Terima Piutang',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget, reason: 'submenu $label');
    }
    // Submenu lain tetap fail-closed selama kuncinya belum diberikan.
    expect(find.text('Kode Akun'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submenu bekas tab tersembunyi bila kuncinya dimatikan admin',
      (tester) async {
    await pakaiDesktop(tester);
    Sesi.instance.aksesMenu = {'laporankeuangan': true};
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    await bukaGrup(tester);

    // Grup tetap tampil (Katalog Laporan memakai kunci induk), tetapi keenam
    // submenu bekas tab tidak boleh ikut muncul tanpa kuncinya masing-masing.
    expect(find.text('Katalog Laporan'), findsOneWidget);
    for (final label in [
      'Saldo Awal (Neraca Awal)',
      'Jurnal Penyesuaian Berkala',
      'Tutup Buku (Laba Ditahan)',
      'Posting Kulakan',
      'Posting Bayar Hutang',
      'Posting Terima Piutang',
    ]) {
      expect(find.text(label), findsNothing, reason: 'submenu $label fail-closed');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('submenu berkunci sendiri muncul setelah kuncinya diberikan',
      (tester) async {
    await pakaiDesktop(tester);
    Sesi.instance.aksesMenu = {
      'laporankeuangan': true,
      'kode_akun': true,
      'grup_akun': true,
      'jenis_transaksi': true,
      'bank_akun': true,
      'jurnal_umum': true,
      'posting_hpp': true,
      'posting_penjualan': true,
    };
    await tester.pumpWidget(aplikasi());
    await tester.pumpAndSettle();
    await bukaGrup(tester);

    for (final label in [
      'Kode Akun',
      'Grup Akun',
      'Jenis Transaksi',
      'Bank',
      'Jurnal Umum',
      'Posting HPP',
      'Posting Penjualan',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget, reason: 'submenu $label');
    }
    expect(tester.takeException(), isNull);
  });
}
