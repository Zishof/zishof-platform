import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/prescription/apotik_resep_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PanggilResep _server({
  List<Map<String, dynamic>>? resep,
  List<Map<String, dynamic>>? baris,
  Map<String, dynamic>? statusDispensing,
  Map<String, dynamic>? hasilCatat,
  List<Map<String, dynamic>>? terkirim,
}) {
  return (aksi, body) async {
    terkirim?.add({'aksi': aksi, ...body});
    switch (aksi) {
      case 'apotik_resep_list':
        return {'status': '00', 'data': resep ?? const []};
      case 'apotik_resep_detail':
        return {'status': '00', 'data': baris ?? const []};
      case 'apotik_dispensing_status':
        return statusDispensing ??
            {'status': '91', 'description': 'belum tersedia'};
      case 'apotik_dispensing_catat':
        return hasilCatat ?? {'status': '00', 'description': 'Tercatat.'};
      default:
        return {'status': '91', 'description': 'Aksi tidak dikenal'};
    }
  };
}

Future<void> _pump(WidgetTester tester, Widget child, Size ukuran) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran),
      child: SizedBox(width: ukuran.width, height: ukuran.height, child: child),
    ),
  ));
  await tester.pumpAndSettle();
}

const _desktop = Size(1500, 900);

final _resepSatu = <String, dynamic>{
  'id': 7,
  'kode': 'RSP-007',
  'diagnosa': 'ISPA',
  'jumlahBaris': 2,
  'ditebus': false,
};

void main() {
  group('Antrean resep', () {
    testWidgets('menampilkan daftar dengan status menunggu', (tester) async {
      await _pump(tester,
          ApotikResepPage(panggil: _server(resep: [_resepSatu])), _desktop);
      expect(find.text('RSP-007'), findsOneWidget);
      // "Menunggu" muncul dua kali dan itu benar: label chip filter DAN pill
      // status pada barisnya.
      expect(find.text('Menunggu'), findsNWidgets(2));
      expect(find.textContaining('ISPA'), findsOneWidget);
    });

    testWidgets('resep sudah ditebus ditandai berbeda', (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            {..._resepSatu, 'ditebus': true}
          ])),
          _desktop);
      expect(find.text('Ditebus'), findsOneWidget);
    });

    testWidgets('antrean kosong memberi petunjuk, bukan layar hampa',
        (tester) async {
      await _pump(tester, ApotikResepPage(panggil: _server()), _desktop);
      expect(find.text('Tidak ada resep menunggu'), findsOneWidget);
    });

    testWidgets('galat server ditampilkan apa adanya', (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: (aksi, body) async =>
                  {'status': '91', 'description': 'Antrean sedang dikunci.'}),
          _desktop);
      expect(find.text('Antrean sedang dikunci.'), findsOneWidget);
    });

    testWidgets('sebelum memilih resep, panel kanan mengajak memilih',
        (tester) async {
      await _pump(tester,
          ApotikResepPage(panggil: _server(resep: [_resepSatu])), _desktop);
      expect(find.text('Pilih resep'), findsOneWidget);
    });
  });

  group('Daftar periksa pra-serah — dari data nyata', () {
    testWidgets('menandai terkendali, high-alert, LASA, cold-chain',
        (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {
              'nama': 'Codein 10 mg',
              'jumlah': 10,
              'stok': 50,
              'satuan': 'tablet',
              'terkendali': true,
              'highAlert': true,
              'lasa': true,
              'coldChain': true,
            }
          ])),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 obat TERKENDALI'), findsOneWidget);
      expect(find.textContaining('1 obat HIGH-ALERT'), findsOneWidget);
      expect(find.textContaining('1 obat LASA'), findsOneWidget);
      expect(find.textContaining('1 obat COLD-CHAIN'), findsOneWidget);
    });

    testWidgets('stok kurang dihitung dari kebutuhan resep', (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Amoxicillin', 'jumlah': 30, 'stok': 5, 'satuan': 'tablet'}
          ])),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stok kurang: Amoxicillin'), findsOneWidget);
      expect(find.textContaining('butuh 30, tersedia 5'), findsOneWidget);
    });

    testWidgets('baris racikan ditandai belum dapat diserahkan',
        (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Puyer Batuk', 'jumlah': 1, 'stok': 10, 'racikan': true}
          ])),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      expect(find.textContaining('baris RACIKAN belum dapat diserahkan'),
          findsOneWidget);
    });

    testWidgets('SELALU menyatakan apa yang BELUM diperiksa sistem (IR-03)',
        (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Paracetamol', 'jumlah': 10, 'stok': 100}
          ])),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      // Tidak boleh ada klaim "tidak ada interaksi/alergi" -- sistem memang
      // belum memeriksanya, dan itu dinyatakan terang-terangan.
      expect(find.textContaining('BELUM memeriksa alergi, interaksi obat'),
          findsOneWidget);
      expect(find.textContaining('Tidak ada peringatan klinis'), findsNothing);
    });
  });

  group('Dispensing IR-05', () {
    testWidgets('server lama tanpa IR-05: bagian dispensing disembunyikan',
        (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Paracetamol', 'jumlah': 1, 'stok': 5}
          ])),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      expect(find.text('Pemeriksaan kedua & konseling'), findsNothing);
    });

    testWidgets('menampilkan tombol saat server mendukung', (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Paracetamol', 'jumlah': 1, 'stok': 5}
          ], statusDispensing: {
            'status': '00',
            'data': const [],
            'sudahDoubleCheck': false,
            'sudahKonseling': false,
          })),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      expect(find.text('Pemeriksaan kedua'), findsOneWidget);
      expect(find.text('Catat konseling'), findsOneWidget);
    });

    testWidgets('yang sudah tercatat menonaktifkan tombolnya', (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Paracetamol', 'jumlah': 1, 'stok': 5}
          ], statusDispensing: {
            'status': '00',
            'sudahDoubleCheck': true,
            'sudahKonseling': false,
            'data': [
              {
                'jenis': 'DOUBLE_CHECK',
                'pelakuUserId': 'apoteker2',
                'waktu': '2026-08-19 10:00:00'
              }
            ],
          })),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      expect(find.text('Sudah diperiksa'), findsOneWidget);
      expect(find.textContaining('oleh apoteker2'), findsOneWidget);
      // OutlinedButton.icon menghasilkan SUBCLASS -> byType tidak cocok.
      final tombol = tester.widget<OutlinedButton>(find
          .ancestor(
              of: find.text('Sudah diperiksa'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton))
          .first);
      expect(tombol.onPressed, isNull);
    });

    testWidgets('penolakan aturan pemeriksa kedua ditampilkan apa adanya',
        (tester) async {
      await _pump(
          tester,
          ApotikResepPage(
              panggil: _server(resep: [
            _resepSatu
          ], baris: [
            {'nama': 'Paracetamol', 'jumlah': 1, 'stok': 5}
          ], statusDispensing: {
            'status': '00',
            'data': const [],
            'sudahDoubleCheck': false,
            'sudahKonseling': false,
          }, hasilCatat: {
            'status': '91',
            'description':
                'DITOLAK: pemeriksa kedua harus akun yang BERBEDA dari penyiap obat (kasir1).'
          })),
          _desktop);
      await tester.tap(find.text('RSP-007'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pemeriksaan kedua'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'kasir1');
      await tester.tap(find.text('Catat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('harus akun yang BERBEDA'), findsOneWidget);
    });
  });
}
