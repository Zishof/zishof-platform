import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_formularium_page.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PanggilFormularium _server({
  List<Map<String, dynamic>>? item,
  Map<String, dynamic>? hasilSimpan,
  List<Map<String, dynamic>>? terkirim,
}) {
  return (aksi, body) async {
    terkirim?.add({'aksi': aksi, ...body});
    switch (aksi) {
      case 'apotik_item_cari':
        return {'status': '00', 'data': item ?? const []};
      case 'apotik_item_profil_simpan':
        return hasilSimpan ?? {'status': '00', 'profilId': 1};
      default:
        return {'status': '91', 'description': 'Aksi tidak dikenal'};
    }
  };
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1400, 900)}) async {
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

final _obat = <String, dynamic>{
  'id': 11,
  'kode': 'OBT-11',
  'nama': 'Amoxicillin 500 mg',
  'satuan': 'tablet',
  'stok': 25,
  'hargaJual': 2500,
  'golonganObat': 'BEBAS',
  'lasa': false,
  'highAlert': false,
  'coldChain': false,
};

void main() {
  testWidgets('menampilkan katalog memakai kartu yang SAMA dengan POS',
      (tester) async {
    await _pump(tester, ApotikFormulariumPage(panggil: _server(item: [_obat])));
    expect(find.byType(MedicationCard), findsOneWidget);
    expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
  });

  testWidgets('kosong memberi petunjuk asal obat baru', (tester) async {
    await _pump(tester, ApotikFormulariumPage(panggil: _server()));
    expect(find.text('Obat tidak ditemukan'), findsOneWidget);
    expect(find.textContaining('modul persediaan/penerimaan'), findsOneWidget);
  });

  testWidgets('galat server ditampilkan apa adanya', (tester) async {
    await _pump(
        tester,
        ApotikFormulariumPage(
            panggil: (aksi, body) async =>
                {'status': '91', 'description': 'Formularium dikunci admin.'}));
    expect(find.text('Formularium dikunci admin.'), findsOneWidget);
  });

  group('Editor profil IR-01 — melengkapi lingkaran baca/tulis', () {
    testWidgets('form memuat nilai yang sudah ada', (tester) async {
      await _pump(
          tester,
          ApotikFormulariumPage(
              panggil: _server(item: [
            {
              ..._obat,
              'golonganObat': 'KERAS',
              'kekuatan': '500 mg',
              'bentukSediaan': 'kaplet',
              'highAlert': true,
            }
          ])));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      expect(find.text('500 mg'), findsWidgets);
      expect(find.text('kaplet'), findsOneWidget);
      // Golongan tersisi dari data server, bukan default.
      expect(find.text('Keras (Rx)'), findsWidgets);
    });

    testWidgets('menyimpan mengirim SELURUH field IR-01 ke server',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
              panggil: _server(item: [_obat], terkirim: terkirim)));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();

      // Cari field lewat LABEL, bukan indeks -- indeks rapuh terhadap
      // perubahan tata letak dialog.
      await tester.enterText(
          find.widgetWithText(TextField, 'Kekuatan'), '250 mg');
      await tester.enterText(
          find.widgetWithText(TextField, 'Bentuk sediaan'), 'sirup');
      // Nyalakan high-alert.
      await tester.tap(find.text('High-alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final kirim =
          terkirim.lastWhere((e) => e['aksi'] == 'apotik_item_profil_simpan');
      expect(kirim['item_id'], 11);
      expect(kirim['kekuatan'], '250 mg');
      expect(kirim['bentuk_sediaan'], 'sirup');
      expect(kirim['high_alert'], isTrue);
      // Field lain tetap ikut supaya server tidak menebak-nebak.
      expect(kirim.containsKey('golongan_obat'), isTrue);
      expect(kirim.containsKey('lasa'), isTrue);
      expect(kirim.containsKey('cold_chain'), isTrue);
    });

    testWidgets('membatalkan dialog TIDAK mengirim apa pun', (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
              panggil: _server(item: [_obat], terkirim: terkirim)));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(terkirim.any((e) => e['aksi'] == 'apotik_item_profil_simpan'),
          isFalse);
    });

    testWidgets('penolakan server ditampilkan apa adanya', (tester) async {
      await _pump(
          tester,
          ApotikFormulariumPage(
              panggil: _server(item: [
            _obat
          ], hasilSimpan: {
            'status': '91',
            'description': 'Golongan obat tidak dikenal.'
          })));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Golongan obat tidak dikenal.'), findsOneWidget);
    });
  });
}
