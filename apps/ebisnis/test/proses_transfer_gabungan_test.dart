import 'dart:io';

import 'package:ebisnis/screens/proses_transfer_screen.dart';
import 'package:ebisnis/services/master_offline.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kontrak **penggabungan menu pencairan** ke dalam satu layar Proses Transfer.
///
/// Permintaan pemilik produk: Proses Transfer, Pembayaran Vendor, dan Proses
/// Transitori berdiri sebagai tiga menu terpisah di grup Keuangan padahal
/// mengerjakan rangkaian yang sama atas dokumen yang sama, sehingga pengguna
/// harus menebak menu mana yang memuat pekerjaannya.
///
/// Dua hal yang mahal bila diam-diam berbalik dan karena itu dikunci di sini:
/// (1) tidak ada kemampuan yang hilang -- setiap layar yang diserap masih
/// dirender, dan (2) hak akses tidak ikut digabung -- tab hanya muncul bila
/// kunci menu modul itu sendiri mengizinkan.
void main() {
  final gabungan =
      File('lib/screens/proses_transfer_screen.dart').readAsStringSync();

  test('layar Proses Transfer memuat ketiga modul pencairan', () {
    // Layar yang diserap dipakai ULANG, bukan disalin ulang.
    expect(gabungan, contains('PengadaanBayarScreen(tersemat: true)'),
        reason: 'Pembayaran Vendor harus tetap dirender');
    expect(gabungan, contains('ProsesTransitoriScreen(tersemat: true)'),
        reason: 'Proses Transitori harus tetap dirender');
    expect(gabungan, contains('PengadaanTransitoriTab()'),
        reason: 'daftar transitori yang menunggu realisasi jangan ikut hilang');

    for (final judul in [
      "text: 'Dasbor'",
      "text: 'Proses Transfer'",
      "text: 'Pembayaran Vendor'",
      "text: 'Transitori Menunggu'",
      "text: 'Proses Transitori'",
    ]) {
      expect(gabungan, contains(judul), reason: 'tab $judul hilang');
    }
  });

  test('hak akses TIDAK ikut digabung: tiap tab digerbangi kunci modulnya', () {
    expect(gabungan, contains("Sesi.instance.bolehMenu('pengadaan_dpc')"));
    expect(gabungan, contains("Sesi.instance.bolehMenu('proses_transitori')"));

    // Tab dan halaman harus dijaga oleh bendera yang SAMA; kalau tidak, jumlah
    // tab dan jumlah halaman berbeda dan TabBarView melempar saat dibuka.
    final jumlahJagaTab = 'if (bolehBayarVendor)'.allMatches(gabungan).length;
    final jumlahJagaTransitori =
        'if (bolehTransitori)'.allMatches(gabungan).length;
    expect(jumlahJagaTab, 4,
        reason: 'dua tab + dua halaman untuk Pembayaran Vendor');
    expect(jumlahJagaTransitori, 2,
        reason: 'satu tab + satu halaman untuk Proses Transitori');
  });

  test('dua menu lama tidak lagi berdiri sendiri di sidebar', () {
    final shell = File('lib/widgets/app_shell.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final awal = shell.indexOf("'Keuangan'");
    expect(awal, isNonNegative);
    final akhir = shell.indexOf('_GrupMenuShell', awal + 10);
    final grupKeuangan =
        shell.substring(awal, akhir > awal ? akhir : shell.length);

    expect(grupKeuangan, contains('MenuEBisnis.prosesTransfer'));
    expect(grupKeuangan, isNot(contains('MenuEBisnis.prosesTransitori')),
        reason: 'Proses Transitori kini tab, bukan menu');
    expect(grupKeuangan, isNot(contains('MenuEBisnis.pengadaanDpc')),
        reason: 'Pembayaran Vendor kini tab, bukan menu');
  });

  test('layar yang diserap tetap dapat berdiri sendiri', () {
    // Mode tersemat adalah TAMBAHAN, bukan pengganti: layarnya masih punya
    // AppShell sendiri sehingga jalur navigasi lama (deep link, tombol dari
    // layar lain) tidak putus.
    for (final berkas in [
      'lib/screens/pengadaan_bayar_screen.dart',
      'lib/screens/proses_transitori_screen.dart',
    ]) {
      final source = File(berkas).readAsStringSync();
      expect(source, contains('this.tersemat = false'),
          reason: '$berkas: bawaan harus berdiri sendiri');
      expect(source, contains('AppShell('),
          reason: '$berkas: kerangka layar mandiri jangan dibuang');
      expect(source, contains('if (widget.tersemat)'),
          reason: '$berkas: cabang tersemat hilang');
    }
  });

  group('render sungguhan', () {
    // Dasbor menyalakan flush periodik MasterOffline; tanpa dimatikan, timer itu
    // masih hidup saat pohon widget dibongkar dan uji gagal oleh invarian
    // "A Timer is still pending" -- pola yang sama dipakai
    // drawer_akuntansi_halaman_test.dart.
    tearDown(() {
      MasterOffline.hentikanTimer();
      Sesi.instance.aksesMenu = {};
    });

    Future<void> pakaiDesktop(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('lima tab tampil dan dapat dibuka tanpa galat', (tester) async {
      await pakaiDesktop(tester);
      Sesi.instance.aksesMenu = {
        'proses_transfer': true,
        'pengadaan_dpc': true,
        'proses_transitori': true,
      };
      await tester.pumpWidget(const MaterialApp(home: ProsesTransferScreen()));
      await tester.pump();

      for (final judul in [
        'Dasbor',
        'Proses Transfer',
        'Pembayaran Vendor',
        'Transitori Menunggu',
        'Proses Transitori',
      ]) {
        expect(find.text(judul), findsWidgets, reason: 'tab $judul tidak tampil');
      }

      // Membuka tiap tab: yang dijaga adalah TIDAK ADA galat tata letak atau
      // ketidakcocokan jumlah tab vs halaman. Isinya sendiri memang kosong --
      // tidak ada server di lingkungan uji.
      for (final judul in ['Pembayaran Vendor', 'Transitori Menunggu', 'Proses Transitori']) {
        await tester.tap(find.text(judul).last);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);

      // Beri waktu timer sekali-jalan (indikator sinkron "kembali diam", dsb.)
      // menyelesaikan dirinya, lalu matikan flush periodiknya. Tanpa ini uji
      // gagal oleh invarian "A Timer is still pending" -- artefak harness,
      // bukan cacat produk.
      MasterOffline.hentikanTimer();
      await tester.pump(const Duration(seconds: 6));
      MasterOffline.hentikanTimer();
    });

    testWidgets('tab modul yang tidak boleh dilihat memang tidak dibuat',
        (tester) async {
      await pakaiDesktop(tester);
      // Peran ini hanya boleh Proses Transfer.
      Sesi.instance.aksesMenu = {
        'proses_transfer': true,
        'pengadaan_dpc': false,
        'proses_transitori': false,
      };
      await tester.pumpWidget(const MaterialApp(home: ProsesTransferScreen()));
      await tester.pump();

      expect(find.text('Pembayaran Vendor'), findsNothing);
      expect(find.text('Transitori Menunggu'), findsNothing);
      expect(find.text('Proses Transitori'), findsNothing);
      expect(find.text('Dasbor'), findsWidgets);
      expect(tester.takeException(), isNull);
      MasterOffline.hentikanTimer();
    });
  });
}
