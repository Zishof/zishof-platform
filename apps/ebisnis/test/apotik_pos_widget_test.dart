import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/pos/apotik_cart_panel.dart';
import 'package:ebisnis/features/apotik/pos/apotik_mode_switcher.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bungkus(Widget child, {Size ukuran = const Size(420, 800)}) {
  return MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran),
      child: Scaffold(
          body: SizedBox(
              width: ukuran.width, height: ukuran.height, child: child)),
    ),
  );
}

/// `FilledButton.icon` menghasilkan SUBCLASS FilledButton, sedangkan
/// `find.byType` mencocokkan runtimeType persis -- gunakan predikat.
final _tombolBayar = find.byWidgetPredicate((w) => w is FilledButton);

ApotikBarisKeranjang _baris({
  int id = 1,
  String nama = 'Paracetamol 500 mg',
  double qty = 2,
  double harga = 3000,
  bool terkendali = false,
  bool lasa = false,
  List<Map<String, dynamic>>? batch,
}) =>
    ApotikBarisKeranjang(
      item: <String, dynamic>{
        'id': id,
        'nama': nama,
        'terkendali': terkendali,
        'lasa': lasa,
      },
      qty: qty,
      harga: harga,
      batch: batch,
    );

void main() {
  group('ApotikModeSwitcher', () {
    testWidgets('menampilkan empat mode dan menandai yang aktif',
        (tester) async {
      await tester.pumpWidget(_bungkus(ApotikModeSwitcher(
        aktif: ApotikModePos.otc,
        onPilih: (_) {},
      )));
      expect(find.text('OTC / Obat Bebas'), findsOneWidget);
      expect(find.text('Resep Dokter'), findsOneWidget);
      expect(find.text('Racikan'), findsOneWidget);
      expect(find.text('Produksi Farmasi'), findsOneWidget);
    });

    testWidgets('mode tanpa dukungan server tidak dapat dipilih',
        (tester) async {
      final dipilih = <ApotikModePos>[];
      await tester.pumpWidget(_bungkus(ApotikModeSwitcher(
        aktif: ApotikModePos.otc,
        onPilih: dipilih.add,
      )));
      await tester.tap(find.text('Racikan'));
      await tester.pump();
      expect(dipilih, isEmpty);

      await tester.tap(find.text('Resep Dokter'));
      await tester.pump();
      expect(dipilih, [ApotikModePos.resep]);
    });

    testWidgets('alasan terkunci tersedia untuk pembaca layar', (tester) async {
      await tester.pumpWidget(_bungkus(ApotikModeSwitcher(
        aktif: ApotikModePos.otc,
        onPilih: (_) {},
      )));
      expect(
          find.bySemanticsLabel(RegExp('Racikan.*belum tersedia dari server')),
          findsOneWidget);
    });
  });

  group('ApotikCartPanel', () {
    testWidgets('keranjang kosong memberi petunjuk, bukan panel hampa',
        (tester) async {
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: ApotikPosController(),
        onUbahQty: (_, __) {},
        onHapus: (_) {},
      )));
      expect(find.text('Keranjang kosong'), findsOneWidget);
      expect(find.textContaining('Cari obat di katalog'), findsOneWidget);
    });

    testWidgets('menampilkan baris, subtotal, dan total', (tester) async {
      final pos = ApotikPosController()..tambah(_baris());
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
      )));
      expect(find.text('Paracetamol 500 mg'), findsOneWidget);
      expect(find.text('× Rp 3.000'), findsOneWidget);
      // Subtotal baris dan total keranjang sama-sama Rp 6.000.
      expect(find.text('Rp 6.000'), findsNWidgets(2));
    });

    testWidgets('quantity stepper menaikkan dan menurunkan qty',
        (tester) async {
      final pos = ApotikPosController()..tambah(_baris(qty: 2));
      var qtyBaru = -1.0;
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (i, q) => qtyBaru = q,
        onHapus: (_) {},
      )));
      await tester.tap(find.byIcon(Icons.add));
      expect(qtyBaru, 3);
      await tester.tap(find.byIcon(Icons.remove));
      expect(qtyBaru, 1);
    });

    testWidgets('tombol bayar TERKUNCI dan alasannya terbaca kasir',
        (tester) async {
      // Obat terkendali tanpa identitas pembeli -> pagar menahan.
      final pos = ApotikPosController()
        ..tambah(_baris(terkendali: true, nama: 'Codein 10 mg'));
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
        onBayar: () {},
      )));
      expect(find.text('Pembayaran ditahan'), findsOneWidget);
      expect(find.textContaining('nama pembeli wajib'), findsOneWidget);
      final tombol = tester.widget<FilledButton>(_tombolBayar);
      expect(tombol.onPressed, isNull);
    });

    testWidgets('tombol bayar aktif saat pagar lolos', (tester) async {
      final pos = ApotikPosController()..tambah(_baris());
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
        onBayar: () {},
      )));
      final tombol = tester.widget<FilledButton>(_tombolBayar);
      expect(tombol.onPressed, isNotNull);
      expect(find.text('Bayar'), findsOneWidget);
    });

    testWidgets('saat memproses tombol terkunci dan menampilkan progres',
        (tester) async {
      final pos = ApotikPosController()..tambah(_baris());
      pos.mulaiBayar();
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
        onBayar: () {},
      )));
      expect(find.text('Memproses…'), findsOneWidget);
      final tombol = tester.widget<FilledButton>(_tombolBayar);
      expect(tombol.onPressed, isNull);
    });

    testWidgets('pesan penahan server ditampilkan apa adanya', (tester) async {
      final pos = ApotikPosController()..tambah(_baris());
      pos.mulaiBayar();
      pos.tandaiGagal('Batch B-12 sudah kedaluwarsa, transaksi ditahan.');
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
      )));
      expect(find.text('Batch B-12 sudah kedaluwarsa, transaksi ditahan.'),
          findsOneWidget);
    });

    testWidgets('alokasi batch kurang ditandai pada barisnya', (tester) async {
      final pos = ApotikPosController()
        ..tambah(_baris(qty: 5, batch: [
          {'kadaluarsa_id': 1, 'qty': 2}
        ]));
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
        onPilihBatch: (_) {},
      )));
      expect(find.textContaining('2/5 unit'), findsOneWidget);
      expect(find.textContaining('belum sama dengan qty'), findsOneWidget);
    });

    testWidgets('badge risiko LASA dan terkendali tampil di keranjang',
        (tester) async {
      final pos = ApotikPosController()
        ..tambah(_baris(lasa: true, terkendali: true))
        ..namaPembeli = 'Budi'
        ..namaDokter = 'dr. Sari';
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
      )));
      expect(find.text('LASA'), findsOneWidget);
      expect(find.text('Terkendali'), findsOneWidget);
    });

    testWidgets('transaksi ditahan menampilkan pill dan tombol lanjutkan',
        (tester) async {
      final pos = ApotikPosController()..tambah(_baris());
      pos.tahan();
      await tester.pumpWidget(_bungkus(ApotikCartPanel(
        pos: pos,
        onUbahQty: (_, __) {},
        onHapus: (_) {},
        onLanjutkan: () {},
      )));
      expect(find.text('Ditahan'), findsOneWidget);
      expect(find.text('Lanjutkan'), findsOneWidget);
    });
  });
}
