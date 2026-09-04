import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/main.dart' as app;
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:ebisnis/screens/login_screen.dart';
import 'package:ebisnis/screens/jurnal_umum_screen.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR',
    defaultValue:
        r'C:\opt\AIS\ais\src\main\docs\pos\manual-posting-keuangan\screenshots-uat');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke UAT Akuntansi dan tangkapan layar asli', (tester) async {
    // Mengikuti area kerja monitor UAT 2560x1440 (tinggi efektif 1392 setelah
    // taskbar). Nilai dapat dioverride di CI/monitor lain tanpa mengubah tes.
    const surfaceWidth =
        int.fromEnvironment('POS_TEST_SURFACE_WIDTH', defaultValue: 2560);
    const surfaceHeight =
        int.fromEnvironment('POS_TEST_SURFACE_HEIGHT', defaultValue: 1392);
    await tester.binding
        .setSurfaceSize(const Size(surfaceWidth * 1.0, surfaceHeight * 1.0));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final penanganGalatTes = FlutterError.onError;
    addTearDown(() => FlutterError.onError = penanganGalatTes);
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(host, isNotEmpty);
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    Map<String, dynamic>? login;
    Object? loginError;
    for (var attempt = 1; attempt <= 4 && login == null; attempt++) {
      try {
        login = await ApiClient.instance.aksi('login', {
          'username': username,
          'password': password,
          'labelPerangkat': 'UAT-Manual-Akuntansi',
        });
      } catch (e) {
        loginError = e;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
    if (login == null) throw StateError('Login UAT gagal: $loginError');
    expect(login['token'], isNotNull, reason: 'Login demo gagal: $login');
    await ApiClient.instance.simpanToken(login['token'] as String);
    app.main();
    // main() memasang penangkap galat produksi. Runner test memulihkan handler
    // bawaannya SEBELUM penantian layar awal, supaya timeout startup tetap
    // dilaporkan sebagai penyebab asli dan bukan assertion handler sekunder.
    FlutterError.onError = (detail) {
      if (detail.exceptionAsString().contains('A RenderFlex overflowed')) {
        // Temuan tata letak tetap dicatat dan difoto, tetapi tidak menghentikan
        // UAT fungsional seluruh submenu/laporan.
        // ignore: avoid_print
        print('UAT_LAYOUT_OVERFLOW=${detail.exceptionAsString()}');
        return;
      }
      penanganGalatTes?.call(detail);
    };
    await _tungguSampai(
      tester,
      () =>
          find.byType(KasirScreen).evaluate().isNotEmpty ||
          find.byType(LoginScreen).evaluate().isNotEmpty,
      alasan: 'Layar awal eBisnis tidak selesai dimuat',
      detik: 180,
    );
    if (find.byType(LoginScreen).evaluate().isNotEmpty) {
      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), username);
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), password);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Masuk'));
    }
    await _tungguSampai(
      tester,
      () =>
          find.byType(KasirScreen).evaluate().isNotEmpty &&
          find.text('admin').evaluate().isNotEmpty &&
          find.text('Kantin Demo').evaluate().isNotEmpty,
      alasan: 'Sesi admin dan Kantin Demo belum selesai dimuat',
      detik: 180,
    );
    // Instalasi/build baru dapat menampilkan dialog penyiapan data lokal. Untuk
    // UAT online dialog ini ditutup lewat pilihan "Nanti" agar tidak menutupi
    // sidebar dan tidak mengubah data yang sedang diuji.
    final nanti = find.text('Nanti');
    if (nanti.evaluate().isNotEmpty) {
      await tester.tap(nanti.last);
      await tester.pump(const Duration(seconds: 1));
    }

    await _ambilGambar(tester, '00-layar-awal-integration');

    final teks = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    // ignore: avoid_print
    print('UAT_VISIBLE_TEXT=${teks.join(' | ')}');

    expect(find.byType(LoginScreen), findsNothing,
        reason: 'Token tersimpan belum membawa tes ke layar POS');
    expect(find.byType(KasirScreen), findsOneWidget);

    const kantinVolumeOnly =
        bool.fromEnvironment('POS_TEST_KANTIN_VOLUME_ONLY');
    if (kantinVolumeOnly) {
      await _ketukSidebar(tester, 'TRANSAKSI & LAPORAN');
      await _ambilGambar(tester, '01-menu-transaksi-laporan');
      await _bukaMenuDanFoto(
          tester, 'Riwayat Penjualan', '02-riwayat-penjualan-52-transaksi');
      await _ketukSidebar(tester, 'MASTER DATA');
      await _bukaMenuDanFoto(tester, 'Kulakan', '03-kulakan-50-faktur-volume');
      await _ketukSidebar(tester, 'AKUNTANSI');
      await _ambilGambar(tester, '04-menu-akuntansi-kantin');
      for (final item in const <(String, String)>[
        ('Posting Penjualan', '05-posting-penjualan-volume'),
        ('Posting HPP', '06-posting-hpp-volume'),
        ('Posting Kulakan', '07-posting-kulakan-volume'),
        ('Draft Jurnal', '08-draft-jurnal-kantin-volume'),
      ]) {
        await _bukaMenuDanFoto(tester, item.$1, item.$2);
      }
      const skipReports = bool.fromEnvironment('POS_TEST_SKIP_REPORTS');
      if (!skipReports) await _ambilLaporanInti(tester);
      return;
    }

    await _ketukSidebar(tester, 'AKUNTANSI');
    await _ambilGambar(tester, '01-menu-akuntansi-terbuka');

    const hanyaMenu = bool.fromEnvironment('POS_TEST_MENU_ONLY');
    if (hanyaMenu) {
      return;
    }

    const hanyaJurnal = bool.fromEnvironment('POS_TEST_JURNAL_ONLY');
    if (hanyaJurnal) {
      await _ketukSidebar(tester, 'Jurnal Umum');
      await _tungguSampai(
        tester,
        () =>
            find.byType(JurnalUmumScreen).evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        alasan: 'Jurnal Umum tidak selesai memuat data',
        detik: 120,
      );
      await _ambilGambar(tester, '30-jurnal-umum-daftar-fullscreen');
      await tester.tap(find.text('Jurnal Baru'));
      await _tungguSampai(
        tester,
        () => find.text('Jurnal Umum Baru').evaluate().isNotEmpty,
        alasan: 'Editor jurnal baru tidak terbuka',
      );
      await tester.enterText(_fieldDenganLabel('Keterangan jurnal *'),
          'Contoh UAT Jurnal Umum - Pembelian ATK tunai');
      await _pilihAkun(tester, 'Akun baris 1', '512.115');
      await tester.enterText(_fieldDenganLabel('Debet').at(0), '750000');
      await _pilihAkun(tester, 'Akun baris 2', '111.101');
      await tester.enterText(_fieldDenganLabel('Kredit').at(1), '750000');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Siap disimpan'), findsOneWidget);
      await _ambilGambar(tester, '31-jurnal-umum-form-seimbang-fullscreen');
      return;
    }

    const hanyaAnggaran = bool.fromEnvironment('POS_TEST_ANGGARAN_ONLY');
    if (hanyaAnggaran) {
      await _bukaMenuDanFoto(
          tester, 'Anggaran (RAB Bulanan)', '01-anggaran-rencana-500-item');
      for (final tab in const <(String, String)>[
        ('Realisasi', '02-anggaran-realisasi-500-item'),
        ('Penggunaan Anggaran', '03-anggaran-penggunaan-500-item'),
      ]) {
        expect(find.text(tab.$1), findsWidgets,
            reason: 'Tab Anggaran ${tab.$1} tidak tersedia');
        await tester.tap(find.text(tab.$1).last);
        await _tungguTanpaSpinner(tester, detik: 120);
        await tester.pump(const Duration(seconds: 1));
        await _ambilGambar(tester, tab.$2);
      }
      await _ketukSidebar(tester, 'Jurnal Umum');
      await _tungguTanpaSpinner(tester, detik: 120);
      await _ambilGambar(tester, '04-jurnal-umum-50-anggaran-terposting');
      await _ambilLaporanInti(tester);
      return;
    }

    const hanyaLaporan = bool.fromEnvironment('POS_TEST_REPORTS_ONLY');
    if (hanyaLaporan) {
      await _ambilLaporanInti(tester);
      return;
    }

    const hanyaSubmenu = bool.fromEnvironment('POS_TEST_SUBMENUS_ONLY');
    const hanyaPosting = bool.fromEnvironment('POS_TEST_POSTING_ONLY');
    if (hanyaPosting) {
      const posting = <(String, String)>[
        ('Posting Kulakan', '11-posting-kulakan'),
        ('Posting Bayar Hutang', '12-posting-bayar-hutang'),
        ('Posting Terima Piutang', '13-posting-terima-piutang'),
      ];
      for (final bagian in posting) {
        await _bukaMenuDanFoto(tester, bagian.$1, bagian.$2);
      }
      return;
    }
    if (hanyaSubmenu) {
      const submenu = <(String, String)>[
        ('Draft Jurnal', '08-draft-jurnal'),
        ('Posting HPP', '09-posting-hpp'),
        ('Posting Penjualan', '10-posting-penjualan'),
        ('Posting Kulakan', '11-posting-kulakan'),
        ('Posting Bayar Hutang', '12-posting-bayar-hutang'),
        ('Posting Terima Piutang', '13-posting-terima-piutang'),
        ('Saldo Awal (Neraca Awal)', '14-saldo-awal'),
        ('Jurnal Penyesuaian Berkala', '15-jurnal-penyesuaian'),
        ('Tutup Buku (Laba Ditahan)', '16-tutup-buku'),
        ('Closing', '17-closing'),
        ('Katalog Laporan', '18-katalog-laporan'),
        ('Anggaran (RAB Bulanan)', '19-anggaran'),
        ('Kode Akun', '20-kode-akun'),
        ('Grup Akun', '21-grup-akun'),
        ('Jenis Transaksi', '22-jenis-transaksi'),
        ('Bank', '23-bank'),
      ];
      for (final bagian in submenu) {
        await _bukaMenuDanFoto(tester, bagian.$1, bagian.$2);
      }
      return;
    }

    await _ketukSidebar(tester, 'Jurnal Umum');
    await _tungguSampai(
      tester,
      () =>
          find.byType(JurnalUmumScreen).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
      alasan: 'Jurnal Umum tidak selesai memuat data',
      detik: 120,
    );
    await _ambilGambar(tester, '02-jurnal-umum-daftar');
    final teksJurnal = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    // ignore: avoid_print
    print('UAT_JURNAL_TEXT=${teksJurnal.join(' | ')}');
    expect(find.byType(JurnalUmumScreen), findsOneWidget);

    const keteranganUat = 'UAT Manual Akuntansi - Setoran modal awal';
    if (find.textContaining(keteranganUat).evaluate().isEmpty) {
      await tester.tap(find.text('Jurnal Baru'));
      await _tungguSampai(
        tester,
        () => find.text('Jurnal Umum Baru').evaluate().isNotEmpty,
        alasan: 'Editor jurnal baru tidak terbuka',
      );
      await _ambilGambar(tester, '03-jurnal-umum-formulir-baru');

      await tester.enterText(
          _fieldDenganLabel('Keterangan jurnal *'), keteranganUat);
      await _pilihAkun(tester, 'Akun baris 1', '111.101');
      await tester.enterText(_fieldDenganLabel('Debet').at(0), '1000000');
      await _pilihAkun(tester, 'Akun baris 2', '800.000');
      await tester.enterText(_fieldDenganLabel('Kredit').at(1), '1000000');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Siap disimpan'), findsOneWidget);
      await _ambilGambar(tester, '04-jurnal-umum-seimbang');

      await tester.tap(find.text('Simpan sebagai Draf'));
      await _tungguSampai(
        tester,
        () =>
            find.text('Jurnal Umum Baru').evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        alasan: 'Penyimpanan jurnal draf tidak selesai',
      );
      await _tungguSampai(
        tester,
        () => find.textContaining(keteranganUat).evaluate().isNotEmpty,
        alasan: 'Draf tersimpan belum muncul pada daftar jurnal',
      );
    }
    expect(find.textContaining('UAT Manual Akuntansi'), findsWidgets);
    await _ambilGambar(tester, '05-jurnal-umum-draf-tersimpan');

    if (find.textContaining('Posting Semua Draf').evaluate().isNotEmpty) {
      await tester.tap(find.textContaining('Posting Semua Draf').first);
      await _tungguSampai(
        tester,
        () => find.text('Posting Semua Draf').evaluate().isNotEmpty,
        alasan: 'Konfirmasi posting jurnal tidak muncul',
      );
      await _ambilGambar(tester, '06-jurnal-umum-konfirmasi-posting');
      await tester.tap(find.widgetWithText(FilledButton, 'Posting'));
      await _tungguSampai(
        tester,
        () =>
            find.byTooltip('Posting ke buku besar').evaluate().isEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        alasan: 'Posting jurnal ke buku besar tidak selesai',
      );
    }
    expect(find.text('Terposting'), findsWidgets);
    await _ambilGambar(tester, '07-jurnal-umum-terposting');

    const submenu = <(String, String)>[
      ('Draft Jurnal', '08-draft-jurnal'),
      ('Posting HPP', '09-posting-hpp'),
      ('Posting Penjualan', '10-posting-penjualan'),
      ('Posting Kulakan', '11-posting-kulakan'),
      ('Posting Bayar Hutang', '12-posting-bayar-hutang'),
      ('Posting Terima Piutang', '13-posting-terima-piutang'),
      ('Saldo Awal (Neraca Awal)', '14-saldo-awal'),
      ('Jurnal Penyesuaian Berkala', '15-jurnal-penyesuaian'),
      ('Tutup Buku (Laba Ditahan)', '16-tutup-buku'),
      ('Closing', '17-closing'),
      ('Katalog Laporan', '18-katalog-laporan'),
      ('Anggaran (RAB Bulanan)', '19-anggaran'),
      ('Kode Akun', '20-kode-akun'),
      ('Grup Akun', '21-grup-akun'),
      ('Jenis Transaksi', '22-jenis-transaksi'),
      ('Bank', '23-bank'),
    ];
    for (final bagian in submenu) {
      await _bukaMenuDanFoto(tester, bagian.$1, bagian.$2);
    }

    await _ambilLaporanInti(tester);
  });
}

Finder _fieldDenganLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

Future<void> _pilihAkun(
    WidgetTester tester, String labelField, String kodeAkun) async {
  await tester.tap(find.text(labelField));
  await _tungguSampai(
    tester,
    () => find.text('Cari kode atau nama akun...').evaluate().isNotEmpty,
    alasan: 'Dialog pemilih $labelField tidak terbuka',
  );
  final pencarian = find.byWidgetPredicate((w) =>
      w is TextField &&
      w.decoration?.hintText == 'Cari kode atau nama akun...');
  await tester.enterText(pencarian, kodeAkun);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _tungguSampai(
    tester,
    () => find.text('Cari kode atau nama akun...').evaluate().isEmpty,
    alasan: 'Akun $kodeAkun belum terpilih',
  );
}

Future<void> _bukaMenuDanFoto(
    WidgetTester tester, String label, String namaGambar) async {
  if (label == 'Posting Kulakan' ||
      label == 'Posting Bayar Hutang' ||
      label == 'Posting Terima Piutang') {
    // Ketiga layar memakai State bertipe sama. Singgah ke layar bertipe lain
    // agar state jenis posting lama tidak dipakai ulang untuk menu berikutnya.
    await _ketukSidebar(tester, 'Katalog Laporan');
    await _tungguTanpaSpinner(tester, detik: 45);
  }
  await _ketukSidebar(tester, label);
  await _tungguSampai(
    tester,
    () => find.text(label).evaluate().isNotEmpty,
    alasan: 'Submenu $label tidak terbuka',
    detik: 45,
  );
  final tabTarget = switch (label) {
    'Jurnal Penyesuaian Berkala' => 'Jurnal Penyesuaian',
    'Tutup Buku (Laba Ditahan)' => 'Tutup Buku',
    'Grup Akun' => 'Grup Akun',
    'Jenis Transaksi' => 'Jenis Transaksi',
    'Bank' => 'Bank',
    _ => null,
  };
  if (tabTarget != null && find.text(tabTarget).evaluate().isNotEmpty) {
    await tester.tap(find.text(tabTarget).last);
    await tester.pump(const Duration(seconds: 1));
  }
  final stabil = await _tungguTanpaSpinner(tester, detik: 90);
  if (label == 'Tutup Buku (Laba Ditahan)') {
    final sampai = find.textContaining('Sampai 2026-09-');
    if (sampai.evaluate().isNotEmpty) {
      await tester.tap(sampai.last);
      await _pilihTanggalDialog(tester, 30);
    }
    if (find.text('Lihat Draf').evaluate().isNotEmpty) {
      await tester.tap(find.text('Lihat Draf').last);
      await _tungguTanpaSpinner(tester, detik: 90);
    }
  }
  var tutupDialog = false;
  if (label == 'Closing' && find.text('Tutup Periode').evaluate().isNotEmpty) {
    await tester.tap(find.text('Tutup Periode').last);
    await _tungguSampai(
      tester,
      () => find.text('Closing Baru').evaluate().isNotEmpty,
      alasan: 'Form pratinjau Closing tidak terbuka',
    );
    tutupDialog = true;
  }
  final teks = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data)
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toSet()
      .take(80)
      .join(' | ');
  // ignore: avoid_print
  print(
      'UAT_MENU=$label STATUS=${stabil ? 'STABIL' : 'MASIH_MEMUAT'} TEXT=$teks');
  await _ambilGambar(tester, namaGambar);
  if (tutupDialog) {
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _pilihTanggalDialog(WidgetTester tester, int hari) async {
  await _tungguSampai(
    tester,
    () => find.byType(DatePickerDialog).evaluate().isNotEmpty,
    alasan: 'Pemilih tanggal tidak terbuka',
  );
  await tester.tap(find.text('$hari').last);
  await tester.tap(find.text('OK'));
  await tester.pump(const Duration(seconds: 1));
}

Future<bool> _tungguTanpaSpinner(WidgetTester tester, {int detik = 60}) async {
  for (var i = 0; i < detik * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return true;
  }
  return false;
}

Future<void> _jalankanLaporan(WidgetTester tester, String idLaporan,
    String judul, String namaGambar) async {
  final pencarian = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Cari laporan...');
  await tester.enterText(pencarian, '');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(pencarian, judul);
  await tester.pump(const Duration(milliseconds: 500));
  // Buka detail memakai id katalog yang stabil. Snapshot cache pada sebagian
  // instalasi lama belum selalu memuat kembali seluruh judul setelah kembali
  // dari laporan pertama, sedangkan endpoint berdasarkan id sudah tersedia.
  Navigator.of(tester.element(pencarian)).push(MaterialPageRoute(
      builder: (_) => LaporanDetailScreen(item: {
            'id': idLaporan,
            'judul': judul,
            'ket': 'Laporan berbasis jurnal terposting — UAT manual Akuntansi',
            'satker': false,
          })));
  await tester.pump(const Duration(seconds: 1));
  await _tungguSampai(
    tester,
    () =>
        find.byType(LaporanDetailScreen).evaluate().isNotEmpty &&
        find.text('Tampilkan').evaluate().isNotEmpty,
    alasan: 'Detail laporan $judul tidak terbuka',
  );
  final sampai = find.text('Tanggal Sampai');
  if (sampai.evaluate().isNotEmpty) {
    final ink = find.ancestor(of: sampai, matching: find.byType(InkWell)).first;
    await tester.tap(ink);
    await _pilihTanggalDialog(tester, 30);
  }
  await tester.tap(find.text('Tampilkan').last);
  await tester.pump(const Duration(milliseconds: 500));
  final selesai = await _tungguTanpaSpinner(tester, detik: 90);
  expect(selesai, isTrue, reason: 'Laporan $judul terus memuat');
  expect(find.textContaining('Gagal'), findsNothing,
      reason: 'Laporan $judul menampilkan pesan gagal');
  await tester.pump(const Duration(seconds: 1));
  await _ambilGambar(tester, namaGambar);
  const captureScroll = bool.fromEnvironment('POS_TEST_CAPTURE_REPORT_SCROLL');
  if (captureScroll) {
    await _ambilGambar(tester, '$namaGambar-atas');
    final scrollable = find.descendant(
      of: find.byType(LaporanDetailScreen),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    expect(scrollable, findsWidgets,
        reason: 'Area gulir vertikal laporan $judul tidak ditemukan');
    final state = tester.state<ScrollableState>(scrollable.first);
    final max = state.position.maxScrollExtent;
    if (max > 0) {
      state.position.jumpTo(max / 2);
      await tester.pump(const Duration(milliseconds: 700));
      await _ambilGambar(tester, '$namaGambar-tengah');
      state.position.jumpTo(max);
      await tester.pump(const Duration(milliseconds: 700));
      await _ambilGambar(tester, '$namaGambar-bawah');
      expect(state.position.pixels, closeTo(max, 1),
          reason: 'Laporan $judul belum mencapai scroll terbawah');
    }
    // AppDataTable dapat tetap mempunyai beberapa halaman setelah viewport
    // mencapai bagian bawah. Maju sampai tombol berikutnya nonaktif, lalu
    // ambil bukti bagian bawah HALAMAN TERAKHIR agar seluruh laporan tercakup.
    for (var halaman = 2; halaman <= 500; halaman++) {
      final tombolBerikut = find.ancestor(
        of: find.descendant(
          of: find.byType(LaporanDetailScreen),
          matching: find.byIcon(Icons.chevron_right),
        ),
        matching: find.byType(IconButton),
      );
      Finder? aktif;
      for (var i = 0; i < tombolBerikut.evaluate().length; i++) {
        final kandidat = tombolBerikut.at(i);
        if (tester.widget<IconButton>(kandidat).onPressed != null) {
          aktif = kandidat;
        }
      }
      if (aktif == null) break;
      await tester.tap(aktif);
      // Pagination laporan bersifat lokal/in-memory; satu frame cukup. Tidak
      // ada request server per halaman, jadi menunggu spinner hanya akan
      // memperlambat laporan besar (Jurnal Umum dapat >150 halaman).
      await tester.pump(const Duration(milliseconds: 50));
    }
    final finalState = tester.state<ScrollableState>(scrollable.first);
    finalState.position.jumpTo(finalState.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 500));
    await _ambilGambar(tester, '$namaGambar-akhir-bawah');
  }
  // ignore: avoid_print
  print('UAT_LAPORAN=$judul STATUS=TAMPIL');
  await tester.tap(find.byType(BackButton));
  await _tungguSampai(
    tester,
    () => find.byType(LaporanDetailScreen).evaluate().isEmpty,
    alasan: 'Tidak dapat kembali dari laporan $judul',
  );
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _ambilLaporanInti(WidgetTester tester) async {
  await _ketukSidebar(tester, 'Katalog Laporan');
  await _tungguTanpaSpinner(tester, detik: 90);
  const laporan = <(String, String, String)>[
    (
      'akn_laba_rugi',
      'Laba Rugi (Berbasis Jurnal Akuntansi)',
      '24-laporan-laba-rugi'
    ),
    ('akn_neraca', 'Neraca (Berbasis Jurnal Akuntansi)', '25-laporan-neraca'),
    (
      'akn_arus_kas',
      'Arus Kas (Berbasis Jurnal Akuntansi)',
      '26-laporan-arus-kas'
    ),
    (
      'akn_jurnal',
      'Keseluruhan Jurnal (Jurnal Umum)',
      '27-laporan-jurnal-umum'
    ),
    (
      'akn_buku_besar',
      'Rincian Buku Besar (per Akun)',
      '28-laporan-buku-besar'
    ),
    (
      'akn_neraca_saldo',
      'Neraca Percobaan (Neraca Saldo)',
      '29-laporan-neraca-saldo'
    ),
  ];
  for (final item in laporan) {
    await _jalankanLaporan(tester, item.$1, item.$2, item.$3);
  }
}

Future<void> _ketukSidebar(WidgetTester tester, String label) async {
  final daftar = find.byType(ListView).first;
  var target = find.descendant(of: daftar, matching: find.text(label));
  for (var i = 0; i < 8 && target.evaluate().isEmpty; i++) {
    await tester.drag(daftar, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 150));
    target = find.descendant(of: daftar, matching: find.text(label));
  }
  for (var i = 0; i < 8 && target.evaluate().isEmpty; i++) {
    await tester.drag(daftar, const Offset(0, 500));
    await tester.pump(const Duration(milliseconds: 150));
    target = find.descendant(of: daftar, matching: find.text(label));
  }
  expect(target, findsOneWidget, reason: 'Menu sidebar $label tidak ditemukan');
  final ink = find.ancestor(of: target, matching: find.byType(InkWell)).first;
  final onTap = tester.widget<InkWell>(ink).onTap;
  expect(onTap, isNotNull, reason: 'Menu sidebar $label tidak aktif');
  onTap!.call();
  await tester.pump(const Duration(seconds: 1));
  if (label == 'AKUNTANSI') {
    await Scrollable.ensureVisible(
      tester.element(target),
      alignment: 0.05,
      duration: Duration.zero,
    );
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _ambilGambar(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
  // Test-only capture: RenderView.layer tidak mempunyai API publik ekuivalen
  // yang dapat menyimpan seluruh jendela Windows tanpa driver eksternal.
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) {
    throw StateError('Render layer $nama tidak tersedia');
  }
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1.0,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Render screenshot $nama gagal');
  final direktori = Directory(_outputDir);
  await direktori.create(recursive: true);
  await File('${direktori.path}\\$nama.png')
      .writeAsBytes(data.buffer.asUint8List(), flush: true);
}

Future<void> _tungguSampai(
  WidgetTester tester,
  bool Function() kondisi, {
  required String alasan,
  int detik = 120,
}) async {
  for (var i = 0; i < detik * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (kondisi()) return;
  }
  fail(alasan);
}
