import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/theme/app_colors.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:ebisnis/widgets/app_components.dart';
import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:ebisnis/widgets/penanda_data_tersimpan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue:
      r'E:\opt\Codex-Worspace\zishof-platform-setup-laporan-20260909\docs\pos\uat-offline-20260909\screenshots',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bukti visual penolakan bisnis dan perilaku offline',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2560, 1392));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const kendala = AppErrorInfo(
      judul: 'Saldo member belum mencukupi',
      pesan:
          'Transaksi tidak dikirim ulang otomatis. Pilih member yang benar, lakukan topup sesuai bukti, atau ganti ke pembayaran lokal yang benar-benar sudah diterima.',
      solusi: [
        'Periksa transaksi AB20909202600019 dan member SAHRUL ARIFIN.',
        'Saldo server Rp3.160 lebih kecil dari nilai transaksi Rp149.500.',
        'Jika pembayaran tunai sudah diterima, pilih Ganti ke Pembayaran Lokal; kode dan rincian transaksi tetap sama.',
        'Jika tetap memakai Voucher Pejuang, lakukan topup resmi lalu kirim satu kali setelah tersambung.',
      ],
      teknis:
          'Action: transaksi_simpan | status: PERLU_KOREKSI | alasan server: Saldo SAHRUL ARIFIN tidak mencukupi; saldo Rp3.160, transaksi Rp149.500 | retry otomatis: dihentikan',
      kodeReferensi: 'AB20909202600019',
    );

    await _pump(
      tester,
      const _HalamanBukti(
        judul: 'Transaksi Pending — perlu koreksi',
        subjudul: 'Pembayaran Voucher Pejuang ditolak oleh aturan saldo server',
        child: AppErrorPanel(info: kendala),
      ),
    );
    expect(find.text('Saldo member belum mencukupi'), findsOneWidget);
    expect(find.text('Informasi Teknis'), findsOneWidget);
    await _potret(tester, '01-transaksi-perlu-koreksi');

    await tester.tap(find.text('Informasi Teknis'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('retry otomatis: dihentikan'), findsOneWidget);
    await _potret(tester, '02-detail-teknis-dibuka');

    await _pump(
      tester,
      _HalamanBukti(
        judul: 'Laporan Penjualan — mode offline',
        subjudul: 'Salinan lokal tetap terlihat dan diberi waktu pembaruan',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PenandaDataTersimpan(
              tampil: true,
              diperbaruiPada: DateTime(2026, 9, 9, 15, 30),
            ),
            const SizedBox(height: 16),
            AppDataTable(
              minWidth: 900,
              columns: const [
                AppTableColumn('Referensi', flex: 2),
                AppTableColumn('Status', flex: 2),
                AppTableColumn('Sumber', flex: 3),
                AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
              ],
              rows: [
                AppTableRowData(cells: [
                  AppTableCell.text('AB20909202600019', flex: 2),
                  AppTableCell.text('PERLU KOREKSI', flex: 2),
                  AppTableCell.text('Voucher Pejuang', flex: 3),
                  AppTableCell.text('Rp149.500',
                      flex: 2, align: TextAlign.right),
                ]),
                AppTableRowData(cells: [
                  AppTableCell.text('AB20909202600041', flex: 2),
                  AppTableCell.text('TERSINKRON', flex: 2),
                  AppTableCell.text('Voucher Pejuang', flex: 3),
                  AppTableCell.text('Rp22.500',
                      flex: 2, align: TextAlign.right),
                ]),
                AppTableRowData(cells: [
                  AppTableCell.text('AB20909202600025', flex: 2),
                  AppTableCell.text('TERSINKRON', flex: 2),
                  AppTableCell.text('Tunai', flex: 3),
                  AppTableCell.text('Rp7.000', flex: 2, align: TextAlign.right),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('salinan tersimpan'), findsOneWidget);
    await _potret(tester, '03-laporan-salinan-lokal');

    await _pump(tester, const _MatriksOffline());
    expect(find.text('Harus menunggu server'), findsWidgets);
    await _potret(tester, '04-matriks-batas-offline');
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: child,
  ));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

class _HalamanBukti extends StatelessWidget {
  final String judul;
  final String subjudul;
  final Widget child;
  const _HalamanBukti({
    required this.judul,
    required this.subjudul,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: const Text('eBisnis POS — UAT Offline'),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(judul,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(subjudul,
                    style:
                        TextStyle(color: AppColors.textSecondaryOf(context))),
                const SizedBox(height: 24),
                AppSectionCard(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MatriksOffline extends StatelessWidget {
  const _MatriksOffline();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (
        'Kantin — Tunai/manual',
        'Tersimpan lokal',
        'Dikirim otomatis saat online'
      ),
      (
        'Kantin — Voucher/saldo/PIN',
        'Harus menunggu server',
        'Mencegah saldo negatif'
      ),
      (
        'Apotek — katalog & batch',
        'Salinan lokal',
        'Waktu cache selalu ditampilkan'
      ),
      (
        'Apotek — pembayaran/obat terkendali',
        'Harus menunggu server',
        'Validasi stok, ED, resep, register'
      ),
      (
        'Sales & master CRUD queueable',
        'Tersimpan lokal',
        'ID sementara + outbox'
      ),
      ('Posting jurnal/closing', 'Draf lokal saja', 'Final setelah ACK server'),
      ('Laporan', 'Salinan lokal', 'Pending belum masuk laporan resmi'),
    ];
    return _HalamanBukti(
      judul: 'Batas layanan offline yang aman',
      subjudul:
          'Status dibuat eksplisit agar operator tidak menganggap draf sebagai transaksi final',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppInfoBanner(
            icon: Icons.shield_outlined,
            color: AppColors.info,
            text:
                'Local-first mencatat pekerjaan aman di perangkat. Otorisasi saldo, stok terpusat, obat terkendali, dan posting final tetap fail-closed sampai server memberi ACK.',
          ),
          const SizedBox(height: 16),
          ...rows.map((r) => Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE3E8EF))),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          flex: 4,
                          child: Text(r.$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700))),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(r.$3),
                          ],
                        ),
                      ),
                    ]),
              )),
        ],
      ),
    );
  }
}

Future<void> _potret(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 300));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer $nama tidak ada.');
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal.');
  final directory = Directory(_outputDir);
  await directory.create(recursive: true);
  final file = File('${directory.path}\\$nama.png');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  if (file.lengthSync() < 5000) {
    throw StateError('Screenshot $nama hanya ${file.lengthSync()} byte.');
  }
}
