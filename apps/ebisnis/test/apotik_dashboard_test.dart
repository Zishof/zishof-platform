import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/dashboard/apotik_dashboard_data.dart';
import 'package:ebisnis/features/apotik/dashboard/apotik_dashboard_page.dart';
import 'package:ebisnis/features/apotik/dashboard/apotik_priority_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Server tiruan: mengembalikan respons sesuai KONTRAK NYATA server
/// (`apotik_resep_list`, `apotik_batch_monitor`, `apotik_item_cari`).
ApotikDashboardLoader _loaderTiruan({
  List<Map<String, dynamic>>? resep,
  List<Map<String, dynamic>>? batch,
  List<Map<String, dynamic>>? item,
  Set<String> gagal = const {},
}) {
  return ApotikDashboardLoader(panggil: (aksi, [body]) async {
    if (gagal.contains(aksi)) {
      return {'status': '91', 'description': 'Endpoint $aksi ditolak server.'};
    }
    return switch (aksi) {
      'apotik_resep_list' => {'status': '00', 'data': resep ?? const []},
      'apotik_batch_monitor' => {'status': '00', 'data': batch ?? const []},
      'apotik_item_cari' => {'status': '00', 'data': item ?? const []},
      _ => {'status': '91', 'description': 'Aksi tidak dikenal'},
    };
  });
}

Widget _bungkus(Widget child, {Size ukuran = const Size(1400, 900)}) {
  return MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(data: MediaQueryData(size: ukuran), child: child),
  );
}

void main() {
  group('ApotikDashboardLoader — hanya memakai data server nyata', () {
    test('menghitung resep menunggu dari field ditebus', () async {
      final r = await _loaderTiruan(resep: [
        {'id': 1, 'kode': 'R-01', 'ditebus': false, 'jumlahBaris': 3},
        {'id': 2, 'kode': 'R-02', 'ditebus': true},
        {'id': 3, 'kode': 'R-03', 'ditebus': false},
      ]).muat();
      expect(r.resepMenunggu, 2);
    });

    test('menghitung stok habis dan obat terbaca', () async {
      final r = await _loaderTiruan(item: [
        {'kode': 'A', 'nama': 'Obat A', 'stok': 10},
        {'kode': 'B', 'nama': 'Obat B', 'stok': 0},
        {'kode': 'C', 'nama': 'Obat C', 'stok': -1},
      ]).muat();
      expect(r.obatTerbaca, 3);
      expect(r.stokHabis, 2);
    });

    test('angka tetap null saat endpoint gagal — TIDAK dipalsukan jadi 0',
        () async {
      final r = await _loaderTiruan(gagal: {'apotik_batch_monitor'}).muat();
      expect(r.batchNearExpiry, isNull);
      expect(r.galat['batch'], contains('ditolak server'));
    });

    test('kegagalan satu sumber tidak menghapus data sumber lain', () async {
      final r = await _loaderTiruan(
        resep: [
          {'id': 1, 'kode': 'R-01', 'ditebus': false}
        ],
        gagal: {'apotik_item_cari'},
      ).muat();
      expect(r.resepMenunggu, 1);
      expect(r.stokHabis, isNull);
    });

    test('tugas expiry diurutkan paling mendesak lebih dulu', () async {
      final kini = DateTime(2026, 8, 19);
      final r = await _loaderTiruan(batch: [
        {'nama': 'Obat Jauh', 'tanggalKadaluarsa': '2026-11-01', 'sisa': 5},
        {'nama': 'Obat Dekat', 'tanggalKadaluarsa': '2026-08-25', 'sisa': 2},
      ]).muat(sekarang: kini);
      final expiry =
          r.tugas.where((t) => t.jenis == ApotikTugasJenis.expiry).toList();
      expect(expiry.first.judul, 'Obat Dekat');
      expect(expiry.first.keterangan, contains('6 hari'));
    });

    test('batch yang sudah lewat ditandai SUDAH kedaluwarsa', () async {
      final r = await _loaderTiruan(batch: [
        {'nama': 'Obat Basi', 'tanggalKadaluarsa': '2026-08-10', 'sisa': 4},
      ]).muat(sekarang: DateTime(2026, 8, 19));
      expect(r.tugas.first.keterangan, contains('SUDAH kedaluwarsa'));
      expect(r.tugas.first.urutan, lessThan(0));
    });

    test('sisaHari menghitung selisih hari kalender', () {
      final kini = DateTime(2026, 8, 19, 23, 30);
      expect(ApotikDashboardLoader.sisaHari('2026-08-20', sekarang: kini), 1);
      expect(ApotikDashboardLoader.sisaHari('2026-08-19', sekarang: kini), 0);
      expect(ApotikDashboardLoader.sisaHari('rusak', sekarang: kini), isNull);
      expect(ApotikDashboardLoader.sisaHari(null), isNull);
    });
  });

  group('ApotikPriorityCard', () {
    testWidgets('menampilkan em dash saat data belum diketahui, bukan 0',
        (tester) async {
      await tester.pumpWidget(_bungkus(const Scaffold(
        body: ApotikPriorityCard(
          ikon: Icons.event_busy_outlined,
          judul: 'Batch',
          angka: null,
          makna: 'x',
          catatan: 'Endpoint belum tersedia',
          tujuanLabel: 'Buka',
        ),
      )));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('Endpoint belum tersedia'), findsOneWidget);
    });
  });

  group('ApotikDashboardPage', () {
    testWidgets('menampilkan prioritas dan daftar tugas dari server',
        (tester) async {
      await tester.pumpWidget(_bungkus(ApotikDashboardPage(
        loader: _loaderTiruan(
          resep: [
            {'id': 1, 'kode': 'R-01', 'ditebus': false, 'jumlahBaris': 2}
          ],
          batch: [
            {
              'nama': 'Amoxicillin',
              'tanggalKadaluarsa': '2026-09-01',
              'sisa': 9
            }
          ],
          item: [
            {'kode': 'B', 'nama': 'Obat Kosong', 'stok': 0}
          ],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Operasional'), findsOneWidget);
      expect(find.text('Resep menunggu'), findsOneWidget);
      expect(find.text('Batch mendekati kedaluwarsa'), findsOneWidget);
      // "Stok habis" wajar muncul dua kali: judul kartu prioritas DAN pill
      // pada baris tugasnya -- keduanya memang informasi berbeda.
      expect(find.text('Stok habis'), findsNWidgets(2));
      // Daftar "Perlu tindakan" berisi item konkret, bukan sekadar angka.
      expect(find.text('Perlu tindakan'), findsOneWidget);
      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(find.text('Obat Kosong'), findsOneWidget);
      expect(find.text('Resep R-01'), findsOneWidget);
    });

    testWidgets('daftar kosong memberi kalimat menenangkan yang jujur',
        (tester) async {
      await tester
          .pumpWidget(_bungkus(ApotikDashboardPage(loader: _loaderTiruan())));
      await tester.pumpAndSettle();
      expect(find.text('Tidak ada pekerjaan mendesak'), findsOneWidget);
    });

    testWidgets('galat sumber ditampilkan terpisah, tidak menutup data lain',
        (tester) async {
      await tester.pumpWidget(_bungkus(ApotikDashboardPage(
        loader: _loaderTiruan(
          resep: [
            {'id': 1, 'kode': 'R-09', 'ditebus': false}
          ],
          gagal: {'apotik_batch_monitor'},
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Sebagian data tidak dapat dimuat'), findsOneWidget);
      expect(find.text('Resep R-09'), findsOneWidget);
    });

    testWidgets('TIDAK membuat kartu untuk metrik yang belum ada backend-nya',
        (tester) async {
      await tester
          .pumpWidget(_bungkus(ApotikDashboardPage(loader: _loaderTiruan())));
      await tester.pumpAndSettle();
      // Cold-chain, SLA, tugas shift, transaksi pending = IR-02/IR-06/IR-10.
      expect(find.textContaining('Cold-chain'), findsNothing);
      expect(find.textContaining('SLA'), findsNothing);
      expect(find.textContaining('Shift'), findsNothing);
    });
  });
}
