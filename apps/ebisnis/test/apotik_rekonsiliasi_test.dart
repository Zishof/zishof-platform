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

    testWidgets(
        'server tanpa sesi kas: dikatakan tidak tersimpan, tanpa tombol',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_sesi_kas_status') {
            return {'status': '91', 'description': 'Aksi tidak dikenal'};
          }
          return _rekap();
        }),
      );
      expect(find.textContaining('TIDAK tersimpan'), findsOneWidget);
      // Tanpa dukungan server, tidak boleh ada tombol yang menyiratkan
      // penguncian angka.
      expect(find.text('Tutup sesi kas'), findsNothing);
      expect(find.textContaining('Buka sesi'), findsNothing);
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

  group('Sesi kas apotek (IR-06)', () {
    Map<String, dynamic> sesiTerbuka() => {
          'status': '00',
          'ada': true,
          'sesi': {
            'id': 7,
            'namaKasir': 'Rina',
            'status': 'BUKA',
            'waktuBuka': '2026-09-02 08:00',
            'modalAwal': 300000,
            'tunaiBerjalan': 1250000,
            'nonTunaiBerjalan': 340000,
            'penjualanBerjalan': 1700000,
            'penjualanTanpaMetode': 110000,
            'kasSeharusnya': 1550000,
          },
        };

    testWidgets('sesi terbuka menampilkan kas seharusnya dari server',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_sesi_kas_status') return sesiTerbuka();
          return _rekap();
        }),
      );
      expect(find.text('Sesi kas berjalan'), findsOneWidget);
      expect(find.text('Penerimaan tunai sejak dibuka'), findsOneWidget);
      expect(find.text('Kas seharusnya sekarang'), findsOneWidget);
      // 300.000 modal + 1.250.000 tunai
      expect(find.text('Rp 1.550.000'), findsWidgets);
      expect(find.text('Tutup sesi kas'), findsOneWidget);
    });

    testWidgets('belum ada sesi: menawarkan membuka, bukan menutup',
        (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_sesi_kas_status') {
            return {'status': '00', 'ada': false};
          }
          return _rekap();
        }),
      );
      expect(find.textContaining('Belum ada sesi kas terbuka'), findsOneWidget);
      expect(find.textContaining('Buka sesi'), findsOneWidget);
      expect(find.text('Tutup sesi kas'), findsNothing);
    });

    testWidgets('menutup sesi mengirim HANYA uang fisik, bukan angka sistem',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_sesi_kas_status') return sesiTerbuka();
          if (aksi == 'apotik_sesi_kas_tutup') {
            terkirim.add(Map<String, dynamic>.from(body));
            return {
              'status': '00',
              'sesi': {
                'totalTunaiSistem': 1250000,
                'kasSeharusnya': 1550000,
                'uangFisik': 1540000,
                'selisih': -10000,
              },
            };
          }
          return _rekap();
        }),
      );
      await tester.enterText(
          find.widgetWithText(TextField, 'Uang fisik dihitung'), '1540000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tutup sesi kas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tutup sesi'));
      await tester.pumpAndSettle();

      expect(terkirim.length, 1);
      expect(terkirim.first['uang_fisik'], 1540000);
      // Angka sistem TIDAK boleh datang dari klien.
      expect(terkirim.first.containsKey('total_tunai'), isFalse);
      expect(terkirim.first.containsKey('selisih'), isFalse);
      expect(find.text('Sesi Kas Ditutup'), findsOneWidget);
      expect(find.textContaining('-Rp 10.000'), findsOneWidget);
    });

    testWidgets('penolakan server ditampilkan apa adanya', (tester) async {
      await _pump(
        tester,
        ApotikRekonsiliasiPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_sesi_kas_status') {
            return {'status': '00', 'ada': false};
          }
          if (aksi == 'apotik_sesi_kas_buka') {
            return {
              'status': '91',
              'description': 'Masih ada sesi kas yang terbuka atas nama Anda.'
            };
          }
          return _rekap();
        }),
      );
      await tester.tap(find.textContaining('Buka sesi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Masih ada sesi kas yang terbuka'),
          findsOneWidget);
    });
  });
}
