import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/procurement/apotik_penerimaan_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BarisPenerimaan _baris({
  String nama = 'Amoxicillin',
  double qty = 10,
  double harga = 1500,
  int? edDalamHari = 400,
}) {
  return BarisPenerimaan(
    item: <String, dynamic>{'id': 1, 'nama': nama},
    qty: qty,
    hargaBeli: harga,
    kedaluwarsa: edDalamHari == null
        ? null
        : DateTime.now().add(Duration(days: edDalamHari)),
  );
}

PanggilTerima _server({
  List<Map<String, dynamic>>? item,
  Map<String, dynamic>? hasilPosting,
  List<Map<String, dynamic>>? terkirim,
}) {
  return (aksi, body) async {
    terkirim?.add({'aksi': aksi, ...body});
    switch (aksi) {
      case 'apotik_item_cari':
        return {'status': '00', 'data': item ?? const []};
      case 'apotik_terima_barang':
        return hasilPosting ??
            {'status': '00', 'jumlahBaris': 1, 'jumlahBatch': 1};
      default:
        return {'status': '91', 'description': 'Aksi tidak dikenal'};
    }
  };
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1400, 950)}) async {
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

void main() {
  group('Pagar penerimaan (fungsi murni)', () {
    test('faktur dan penyedia wajib', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: '', penyedia: '', baris: [_baris()]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('Nomor faktur wajib'));
      expect(p.alasan.join(), contains('penyedia/PBF wajib'));
    });

    test('minimal satu baris', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1', penyedia: 'PBF A', baris: []);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('Minimal satu baris'));
    });

    test('tanggal kedaluwarsa WAJIB — lot tanpa ED tak dapat diurut FEFO', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1',
          penyedia: 'PBF A',
          baris: [_baris(edDalamHari: null)]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('tanggal kedaluwarsa wajib'));
      expect(p.alasan.join(), contains('FEFO'));
    });

    test('barang yang SUDAH kedaluwarsa ditolak diterima', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1', penyedia: 'PBF A', baris: [_baris(edDalamHari: -3)]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('sudah lewat'));
    });

    test('qty nol ditolak', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1', penyedia: 'PBF A', baris: [_baris(qty: 0)]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('qty harus lebih dari 0'));
    });

    test('ED dekat MEMPERINGATKAN tapi tidak menahan', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1', penyedia: 'PBF A', baris: [_baris(edDalamHari: 30)]);
      expect(p.boleh, isTrue);
      expect(p.peringatan.join(), contains('30 hari menuju kedaluwarsa'));
    });

    test('harga beli nol memperingatkan tapi tidak menahan', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1', penyedia: 'PBF A', baris: [_baris(harga: 0)]);
      expect(p.boleh, isTrue);
      expect(p.peringatan.join(), contains('harga beli 0'));
    });

    test('penerimaan sah lolos tanpa alasan maupun peringatan', () {
      final p = ApotikPenerimaanPage.periksa(
          noFaktur: 'F-1', penyedia: 'PBF A', baris: [_baris()]);
      expect(p.boleh, isTrue);
      expect(p.alasan, isEmpty);
      expect(p.peringatan, isEmpty);
    });
  });

  group('Layar penerimaan', () {
    testWidgets('awalnya kosong dan tombol posting terkunci', (tester) async {
      await _pump(tester, ApotikPenerimaanPage(panggil: _server()));
      expect(find.text('Belum ada baris'), findsOneWidget);
      final tombol = tester.widget<FilledButton>(
          find.byWidgetPredicate((w) => w is FilledButton));
      expect(tombol.onPressed, isNull);
    });

    testWidgets('alasan penahan terbaca petugas', (tester) async {
      await _pump(tester, ApotikPenerimaanPage(panggil: _server()));
      expect(find.text('Belum dapat diposting'), findsOneWidget);
      expect(find.textContaining('Nomor faktur wajib'), findsOneWidget);
    });

    testWidgets('menambah obat dari pencarian membuat baris', (tester) async {
      await _pump(
          tester,
          ApotikPenerimaanPage(
              panggil: _server(item: [
            {'id': 5, 'kode': 'OBT-5', 'nama': 'Paracetamol', 'stok': 3}
          ])));
      await tester.enterText(
          find.widgetWithText(TextField, 'Cari nama obat atau kode…'), 'para');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paracetamol').last);
      await tester.pumpAndSettle();
      expect(find.text('Baris penerimaan (1)'), findsOneWidget);
    });

    testWidgets('TIDAK menampilkan field yang belum didukung server (IR-09)',
        (tester) async {
      await _pump(tester, ApotikPenerimaanPage(panggil: _server()));
      // Nomor PO, penerimaan sebagian, dan bukti suhu belum ada di backend.
      expect(find.textContaining('Nomor PO'), findsNothing);
      expect(find.textContaining('Suhu'), findsNothing);
      expect(find.textContaining('Partial'), findsNothing);
    });
  });
}
