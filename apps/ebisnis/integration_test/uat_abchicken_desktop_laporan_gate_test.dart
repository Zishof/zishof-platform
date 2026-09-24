import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR');

const _laporan = <Map<String, String>>[
  {
    'id': 'akn_jurnal',
    'judul': 'Keseluruhan Jurnal (Jurnal Umum)',
    'ket': 'Seluruh jurnal terposting tenant AB Chicken.',
    'bukti': 'Hanya jurnal terposting dan tidak dibatalkan.',
    'nama': '20-keseluruhan-jurnal',
  },
  {
    'id': 'akn_buku_besar',
    'judul': 'Rincian Buku Besar (per Akun)',
    'ket': 'Mutasi debit dan kredit dikelompokkan per akun.',
    'bukti': 'Mutasi terposting dikelompokkan per akun.',
    'nama': '21-buku-besar',
  },
  {
    'id': 'akn_neraca_saldo',
    'judul': 'Neraca Percobaan (Neraca Saldo)',
    'ket': 'Kontrol keseimbangan total debit dan kredit.',
    'bukti': 'Total debit dan kredit bersumber dari jurnal terposting.',
    'nama': '22-neraca-saldo',
  },
  {
    'id': 'akn_laba_rugi',
    'judul': 'Laba Rugi (Berbasis Jurnal Akuntansi)',
    'ket': 'Pendapatan, beban, dan laba bersih dari jurnal terposting.',
    'bukti': 'Dihitung hanya dari jurnal tenant yang terposting.',
    'nama': '23-laba-rugi',
  },
  {
    'id': 'akn_neraca',
    'judul': 'Neraca (Berbasis Jurnal Akuntansi)',
    'ket': 'Posisi aset, liabilitas, dan ekuitas tenant.',
    'bukti':
        'Posisi kumulatif sampai tanggal akhir; laba berjalan disajikan sebagai ekuitas.',
    'nama': '24-neraca',
  },
  {
    'id': 'akn_arus_kas',
    'judul': 'Arus Kas (Berbasis Jurnal Akuntansi)',
    'ket': 'Penerimaan, pengeluaran, dan saldo kas/bank.',
    'bukti': 'Mutasi kas/bank hanya dari jurnal tenant terposting.',
    'nama': '25-arus-kas',
  },
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('laporan akuntansi AB Chicken penuh dan bernilai di POS Desktop',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const contextPath = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(host, isNotEmpty);
    expect(_outputDir, isNotEmpty);

    await tester.binding.setSurfaceSize(const Size(2560, 1392));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CoreDb.configureStorage('abchicken_uat_laporan');
    await CoreDb.instance.db;
    addTearDown(() => CoreDb.instance.tutup());

    await ServerConfig.instance
        .simpan(host: host, contextPath: contextPath, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-AB-Chicken-Laporan-Desktop',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    final hasil = StringBuffer('urutan,id,judul,baris,hasil\n');
    for (var i = 0; i < _laporan.length; i++) {
      final laporan = _laporan[i];
      await _bukaLaporan(tester, laporan);
      final langsung = await ApiClient.instance.aksi('laporan_jalankan', {
        'r': laporan['id'],
        'tglMulai': '2026-09-01',
        'tglSampai': '2026-09-30',
        'satkerId': '0',
      });
      final jumlah = (langsung['baris'] as List? ?? const []).length;
      expect(jumlah, greaterThan(0),
          reason: '${laporan['judul']} tidak boleh kosong.');
      hasil.writeln(
          '${i + 1},${laporan['id']},"${laporan['judul']}",$jumlah,LULUS');
    }

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);
    await File('${dir.path}\\hasil-gate-laporan-desktop.csv')
        .writeAsString(hasil.toString(), flush: true);
  });
}

Future<void> _bukaLaporan(
    WidgetTester tester, Map<String, String> laporan) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: LaporanDetailScreen(
      item: {
        'id': laporan['id'],
        'judul': laporan['judul'],
        'ket': laporan['ket'],
        'satker': true,
      },
      satuanKerja: const [
        {'id': 0, 'kode': 'TEN-2026-000001', 'nama': 'AB Chicken'}
      ],
      satuanKerjaDefault: 0,
    ),
  ));
  await _beriWaktu(tester, detik: 2);

  final tanggalAkhir = find.text('09-09-2026');
  expect(tanggalAkhir, findsOneWidget,
      reason: 'Filter tanggal akhir laporan tidak ditemukan.');
  await tester.tap(tanggalAkhir, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  final hari30 = find.text('30');
  expect(hari30, findsWidgets, reason: 'Tanggal 30 September tidak ditemukan.');
  await tester.tap(hari30.last, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
  final ok = find.text('OK');
  expect(ok, findsOneWidget);
  await tester.tap(ok, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));

  final tampilkan = find.text('Tampilkan');
  expect(tampilkan, findsOneWidget);
  await tester.tap(tampilkan, warnIfMissed: false);
  await _tunggu(
      tester, () => find.text(laporan['bukti']!).evaluate().isNotEmpty,
      alasan: '${laporan['judul']} tidak selesai dirender.');
  expect(find.text('Tidak ada data untuk filter yang dipilih.'), findsNothing,
      reason: '${laporan['judul']} tampil kosong.');
  await _potret(tester, laporan['nama']!);

  if (laporan['id'] == 'akn_jurnal') {
    final berikut = find.byIcon(Icons.chevron_right);
    expect(berikut, findsOneWidget);
    for (var halaman = 1; halaman < 48; halaman++) {
      await tester.tap(berikut, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await _potret(tester, '${laporan['nama']}-halaman-terakhir');
  }
}

Future<void> _tunggu(WidgetTester tester, bool Function() syarat,
    {required String alasan, int detik = 90}) async {
  final batas = DateTime.now().add(Duration(seconds: detik));
  while (DateTime.now().isBefore(batas)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (syarat()) return;
  }
  fail(alasan);
}

Future<void> _beriWaktu(WidgetTester tester, {required int detik}) async {
  for (var i = 0; i < detik * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<String> _potret(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 400));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) {
    throw StateError('Render layer $nama tidak tersedia.');
  }
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal dibuat.');
  final dir = Directory(_outputDir);
  await dir.create(recursive: true);
  final file = File('${dir.path}\\$nama.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  expect(file.lengthSync(), greaterThan(10000));
  return file.path;
}
