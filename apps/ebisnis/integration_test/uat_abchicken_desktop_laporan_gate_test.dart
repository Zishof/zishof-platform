import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/app_setting.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/screens/laporan_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/theme/app_colors.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR');

const _laporan = <Map<String, String>>[
  {
    'id': 'akn_neraca',
    'judul': 'Neraca (Posisi Keuangan) — Berbasis Jurnal',
    'ket': 'Posisi aset, liabilitas, dan ekuitas kumulatif sampai tanggal akhir.',
    'nama': '01-neraca',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_laba_rugi',
    'judul': 'Laba Rugi (Berbasis Jurnal Akuntansi)',
    'ket': 'Pendapatan, beban, dan laba bersih dari jurnal terposting.',
    'nama': '02-laba-rugi',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_perubahan_ekuitas',
    'judul': 'Laporan Perubahan Ekuitas',
    'ket': 'Perubahan modal disetor, saldo laba ditahan, dan laba berjalan.',
    'nama': '03-perubahan-ekuitas',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_arus_kas',
    'judul': 'Arus Kas (Berbasis Jurnal Akuntansi)',
    'ket': 'Penerimaan, pengeluaran, dan saldo kas/bank.',
    'nama': '04-arus-kas',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_calk',
    'judul': 'Catatan atas Laporan Keuangan (CALK)',
    'ket': 'Penjelasan kebijakan akuntansi dan rincian pos laporan keuangan.',
    'nama': '05-calk',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_lr_2periode',
    'judul': 'Laba Rugi — 2 Periode (Berbasis Jurnal)',
    'ket': 'Periode berjalan dibanding periode sebelumnya yang sama panjang.',
    'nama': '06-laba-rugi-komparatif',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_neraca_2tanggal',
    'judul': 'Neraca — 2 Tanggal (Berbasis Jurnal)',
    'ket': 'Saldo tiap akun neraca per Tgl Mulai vs per Tgl Sampai beserta perubahannya.',
    'nama': '07-neraca-komparatif',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_lr_12bulan',
    'judul': 'Laba Rugi — 12 Bulan (Berbasis Jurnal)',
    'ket': 'Dua belas bulan berakhir pada bulan Tgl Sampai, satu kolom per bulan.',
    'nama': '08-laba-rugi-12bulan',
    'tglMulai': '2026-10-01',
    'tglSampai': '2026-10-06',
  },
  {
    'id': 'akn_neraca_lajur',
    'judul': 'Neraca Lajur (Kertas Kerja)',
    'ket': 'Saldo tiap akun dipilah ke kolom Laba Rugi dan Neraca — kertas kerja tutup buku.',
    'nama': '09-neraca-lajur',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_arus_kas_aktivitas',
    'judul': 'Arus Kas per Aktivitas (Operasional/Investasi/Pendanaan)',
    'ket': 'Arus kas dikelompokkan ke aktivitas operasional, investasi, dan pendanaan.',
    'nama': '10-arus-kas-aktivitas',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_neraca_saldo',
    'judul': 'Neraca Percobaan (Neraca Saldo)',
    'ket': 'Kontrol keseimbangan total debit dan kredit dari jurnal terposting.',
    'nama': '11-neraca-saldo',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_buku_besar',
    'judul': 'Rincian Buku Besar (per Akun)',
    'ket': 'Mutasi debit dan kredit dikelompokkan per akun.',
    'nama': '12-buku-besar',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_jurnal',
    'judul': 'Keseluruhan Jurnal (Jurnal Umum)',
    'ket': 'Seluruh jurnal terposting tenant.',
    'nama': '13-jurnal-umum',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_jurnal_penyesuaian',
    'judul': 'Jurnal Penyesuaian (AJP)',
    'ket': 'Jurnal penyesuaian akhir periode untuk akrual, depresiasi, dan amortisasi.',
    'nama': '14-jurnal-penyesuaian',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'ar_saldo',
    'judul': 'Rincian Saldo Piutang Pelanggan',
    'ket': 'Daftar piutang aktif per pelanggan.',
    'nama': '15-rincian-piutang',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'ar_umur_piutang',
    'judul': 'Analisis Umur Piutang (Aging)',
    'ket': 'Klasifikasi piutang lancar, 30 hari, 60 hari, 90 hari, dan >90 hari.',
    'nama': '16-umur-piutang',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'ap_saldo_supplier',
    'judul': 'Rincian Saldo Hutang Supplier',
    'ket': 'Daftar kewajiban hutang dagang kepada pemasok / vendor.',
    'nama': '17-rincian-utang',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'ap_umur_utang',
    'judul': 'Analisis Umur Hutang Supplier',
    'ket': 'Klasifikasi hutang dagang berdasarkan tanggal jatuh tempo.',
    'nama': '18-umur-utang',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_aset_tetap',
    'judul': 'Daftar Aset Tetap & Akumulasi Penyusutan',
    'ket': 'Rincian perolehan aset tetap, tarif penyusutan, akumulasi, dan nilai buku.',
    'nama': '19-aset-tetap',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_rekon_ikhtisar',
    'judul': 'Ikhtisar Rekonsiliasi Kas & Bank',
    'ket': 'Pencocokan saldo buku kas/bank dengan rekening koran bank.',
    'nama': '20-rekonsiliasi-bank',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'sed_stok_harian',
    'judul': 'Rincian Persediaan & Valuasi HPP',
    'ket': 'Posisi persediaan bahan baku dan produk jadi beserta nilai perolehannya.',
    'nama': '21-persediaan-hpp',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
  },
  {
    'id': 'akn_anggaran',
    'judul': 'Laporan Anggaran vs Realisasi (RAB)',
    'ket': 'Evaluasi ketercapaian anggaran pendapatan dan realisasi belanja.',
    'nama': '22-anggaran-realisasi',
    'tglMulai': '2026-01-01',
    'tglSampai': '2026-09-30',
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
    const https = bool.fromEnvironment('POS_TEST_HTTPS', defaultValue: true);
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(host, isNotEmpty);
    expect(_outputDir, isNotEmpty);

    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CoreDb.configureStorage('abchicken_uat_laporan');
    await CoreDb.instance.db;
    addTearDown(() => CoreDb.instance.tutup());

    await ServerConfig.instance
        .simpan(host: host, contextPath: contextPath, https: https);
    await ApiClient.instance.muatTokenTersimpan();
    if (!ApiClient.instance.sudahLogin) {
      final login = await ApiClient.instance.aksi('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-AB-Chicken-Laporan-Desktop',
      });
      await ApiClient.instance.simpanToken(login['token'] as String);
    }

    final konf = await ApiClient.instance.aksi('konfigurasi');
    Sesi.instance.terapkanKonfig(konf);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 6});
    Sesi.instance.tokoId = 6;
    Sesi.instance.tokoNama = 'AB Chicken Pusat';
    AppColors.primary = AppSetting.temaBawaan.warna;

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);

    // 1. Potret Katalog Laporan (LaporanScreen)
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const LaporanScreen(
        aksiKatalog: 'laporan_katalog',
        menuAktif: MenuEBisnis.laporanLaporan,
      ),
    ));
    await _beriWaktu(tester, detik: 2);
    final nanti = find.text('Nanti');
    if (nanti.evaluate().isNotEmpty) {
      await tester.tap(nanti);
      await _beriWaktu(tester, detik: 1);
    }
    await _potret(tester, '00-katalog-laporan-keuangan');

    // 2. Loop dan Potret Tiap Laporan
    final hasil = StringBuffer('urutan,id,judul,baris,hasil\n');
    for (var i = 0; i < _laporan.length; i++) {
      final laporan = _laporan[i];
      final langsung = await ApiClient.instance.aksi('laporan_jalankan', {
        'r': laporan['id'],
        'tglMulai': laporan['tglMulai'] ?? '2026-01-01',
        'tglSampai': laporan['tglSampai'] ?? '2026-09-30',
        'tokoId': 6,
      });
      final baris = langsung['baris'] as List? ?? const [];
      final jumlah = baris.length;
      expect(jumlah, greaterThan(0),
          reason: '${laporan['judul']} tidak boleh kosong.');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: LaporanDetailScreen(
          item: {
            'id': laporan['id'],
            'judul': laporan['judul'],
            'ket': laporan['ket'],
            'tglMulai': laporan['tglMulai'],
            'tglSampai': laporan['tglSampai'],
            'satker': true,
          },
          satuanKerja: const [],
          hasilAwal: langsung,
        ),
      ));
      await _beriWaktu(tester, detik: 1);
      await _potret(tester, laporan['nama']!);

      hasil.writeln(
          '${i + 1},${laporan['id']},"${laporan['judul']}",$jumlah,LULUS');
    }

    await File('${dir.path}\\hasil-gate-laporan-desktop.csv')
        .writeAsString(hasil.toString(), flush: true);
  });
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
