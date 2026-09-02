import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/reports/apotik_rekonsiliasi_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _rekap({
  double tunai = 500000,
  double nonTunai = 200000,
  double penjualan = 700000,
}) {
  return {
    'status': '00',
    'dari': '2026-09-02',
    'sampai': '2026-09-02',
    'perMetode': [
      {'nama': 'Tunai', 'tunai': true, 'jumlahTransaksi': 12, 'nominal': tunai},
      {
        'nama': 'QRIS',
        'tunai': false,
        'jumlahTransaksi': 4,
        'nominal': nonTunai
      },
    ],
    'totalTunai': tunai,
    'totalNonTunai': nonTunai,
    'totalPembayaran': tunai + nonTunai,
    'jumlahTransaksi': 16,
    'penjualanLedger': penjualan,
    'selisihTanpaMetode': penjualan - (tunai + nonTunai),
  };
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1100, 900)}) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: ukuran),
        child:
            SizedBox(width: ukuran.width, height: ukuran.height, child: child),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('Hitung laci (fungsi murni)', () {
    test('kas seharusnya = modal awal + penerimaan TUNAI saja', () {
      final h = ApotikRekonsiliasiPage.hitung(
          modalAwal: 300000, penerimaanTunai: 500000, uangFisik: 800000);
      // Penerimaan non-tunai tidak boleh ikut: uangnya tak pernah masuk laci.
      expect(h.kasSeharusnya, 800000);
      expect(h.cocok, isTrue);
      expect(h.selisih, 0);
    });

    test('uang fisik kurang dinyatakan sebagai KURANG, bukan sekadar warna',
        () {
      final h = ApotikRekonsiliasiPage.hitung(
          modalAwal: 100000, penerimaanTunai: 500000, uangFisik: 560000);
      expect(h.cocok, isFalse);
      expect(h.selisih, -40000);
      expect(h.keterangan, contains('KURANG'));
    });

    test('uang fisik lebih dinyatakan sebagai LEBIH', () {
      final h = ApotikRekonsiliasiPage.hitung(
          modalAwal: 100000, penerimaanTunai: 500000, uangFisik: 610000);
      expect(h.selisih, 10000);
      expect(h.keterangan, contains('LEBIH'));
    });

    test('pembulatan di bawah satu rupiah dianggap cocok', () {
      final h = ApotikRekonsiliasiPage.hitung(
          modalAwal: 0, penerimaanTunai: 1000.4, uangFisik: 1000.0);
      expect(h.cocok, isTrue);
    });
  });

  group('Layar rekonsiliasi', () {
    testWidgets('menampilkan rekap per metode dan pemisahan tunai',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async => _rekap()),
      );
      expect(find.textContaining('Uang masuk per metode'), findsOneWidget);
      expect(find.textContaining('Tunai  · tunai'), findsOneWidget);
      expect(find.textContaining('QRIS  · non-tunai'), findsOneWidget);
      expect(find.text('Penerimaan tunai'), findsOneWidget);
      expect(find.text('Penerimaan non-tunai'), findsOneWidget);
    });

    testWidgets('kas seharusnya memakai penerimaan tunai dari server',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async => _rekap()),
      );
      await tester.enterText(
          find.widgetWithText(TextField, 'Modal awal'), '100000');
      await tester.pumpAndSettle();
      // 100.000 modal + 500.000 tunai (bukan + 200.000 QRIS)
      expect(find.text('Rp 600.000'), findsWidgets);
    });

    testWidgets('selisih tanpa metode dijelaskan, bukan disembunyikan',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(
            panggil: (aksi, body) async =>
                _rekap(tunai: 400000, nonTunai: 100000, penjualan: 700000)),
      );
      expect(find.text('Penjualan tanpa metode tercatat'), findsOneWidget);
      expect(find.textContaining('BUKAN kekurangan kas'), findsOneWidget);
    });

    testWidgets('tanpa selisih, catatan itu tidak ikut muncul', (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(
            panggil: (aksi, body) async =>
                _rekap(tunai: 500000, nonTunai: 200000, penjualan: 700000)),
      );
      expect(find.text('Penjualan tanpa metode tercatat'), findsNothing);
    });

    testWidgets('menyatakan terus terang bahwa lembar ini tidak tersimpan',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async => _rekap()),
      );
      expect(find.textContaining('TIDAK tersimpan di server'), findsOneWidget);
      // Tidak boleh ada tombol yang menyiratkan penguncian angka di server.
      expect(find.textContaining('Tutup Shift'), findsNothing);
      expect(find.textContaining('Tutup Kas'), findsNothing);
    });

    testWidgets('kegagalan server ditampilkan apa adanya', (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(
            panggil: (aksi, body) async => {
                  'status': '91',
                  'description': 'Aksi tidak dikenal: apotik_laporan_pembayaran'
                }),
      );
      expect(find.textContaining('apotik_laporan_pembayaran'), findsOneWidget);
    });
  });
}
