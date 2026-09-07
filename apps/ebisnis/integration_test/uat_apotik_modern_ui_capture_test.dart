import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-modern',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bukti layar kasir modern desktop lebar dengan 100 data',
      (tester) async {
    await _tampilkanDanAmbil(
      tester,
      ukuran: const Size(1920, 1080),
      nama: '01-kasir-modern-desktop-1920',
    );
    expect(find.text('100 ditampilkan dari 100 data'), findsOneWidget);
  });

  testWidgets('bukti layar kasir modern laptop dengan 100 data',
      (tester) async {
    await _tampilkanDanAmbil(
      tester,
      ukuran: const Size(1366, 768),
      nama: '02-kasir-modern-laptop-1366',
    );
    expect(find.text('100 ditampilkan dari 100 data'), findsOneWidget);
  });

  testWidgets('bukti layar kasir modern tablet dengan 100 data',
      (tester) async {
    await _tampilkanDanAmbil(
      tester,
      ukuran: const Size(768, 1024),
      nama: '03-kasir-modern-tablet-768',
    );
    expect(find.text('Tebus Resep'), findsOneWidget);
    expect(find.text('100 ditampilkan dari 100 data'), findsOneWidget);
  });

  testWidgets('bukti layar kasir modern ponsel dengan 100 data',
      (tester) async {
    await _tampilkanDanAmbil(
      tester,
      ukuran: const Size(390, 844),
      nama: '04-kasir-modern-mobile-390',
    );
    expect(find.text('Tebus Resep'), findsOneWidget);
    expect(find.text('100 ditampilkan dari 100 data'), findsOneWidget);
  });

  testWidgets('bukti keranjang melekat pada ponsel setelah memilih obat',
      (tester) async {
    await _tampilkanDanAmbil(
      tester,
      ukuran: const Size(390, 844),
      nama: '05-kasir-modern-mobile-keranjang-390',
      sebelumAmbil: () async {
        await tester.tap(find.byIcon(Icons.add_shopping_cart_outlined).first);
        await tester.pumpAndSettle();
      },
    );
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('Keranjang'), findsWidgets);
  });
}

Future<void> _tampilkanDanAmbil(
  WidgetTester tester, {
  required Size ukuran,
  required String nama,
  Future<void> Function()? sebelumAmbil,
}) async {
  tester.view.physicalSize = ukuran;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Arial',
      extensions: const [ApotikDesignTokens.light],
    ),
    home: ApotikPosPage(panggil: _panggil),
  ));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(seconds: 1));
  if (sebelumAmbil != null) await sebelumAmbil();
  await _ambilGambar(tester, nama);
}

Future<Map<String, dynamic>> _panggil(
    String aksi, Map<String, dynamic> body) async {
  if (aksi == 'apotik_item_cari') {
    return {
      'status': '00',
      'total': 100,
      'data': List.generate(100, _obat),
    };
  }
  if (aksi == 'apotik_cara_bayar_list') {
    return {
      'status': '00',
      'data': const [
        {'id': 1, 'nama': 'Tunai'},
        {'id': 2, 'nama': 'QRIS'},
        {'id': 3, 'nama': 'Kartu Debit'},
      ],
    };
  }
  return {'status': '00', 'data': const []};
}

Map<String, dynamic> _obat(int indeks) {
  const zat = [
    'Paracetamol',
    'Amoxicillin',
    'Cetirizine',
    'Omeprazole',
    'Metformin',
    'Amlodipine',
    'Salbutamol',
    'Acetylcysteine',
  ];
  const bentuk = ['Tablet', 'Kapsul', 'Sirup', 'Drops'];
  final nomor = indeks + 1;
  final namaZat = zat[indeks % zat.length];
  final sediaan = bentuk[indeks % bentuk.length];
  return {
    'id': nomor,
    'kode': 'DEMO-OBT-${nomor.toString().padLeft(5, '0')}',
    'nama': '$namaZat ${100 + (indeks % 9) * 25} mg $sediaan',
    'kandungan': namaZat,
    'bentukSediaan': sediaan,
    'kekuatan': '${100 + (indeks % 9) * 25} mg',
    'satuan': sediaan.toLowerCase(),
    'stok': 18 + (indeks * 7) % 180,
    'hargaJual': 2500 + (indeks * 1700) % 98000,
    'lasa': indeks % 13 == 0,
    'highAlert': indeks % 19 == 0,
    'coldChain': indeks % 23 == 0,
    'terkendali': indeks % 29 == 0,
    'golonganObat': indeks % 5 == 0 ? 'KERAS' : 'BEBAS',
  };
}

Future<void> _ambilGambar(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
  // Test-only capture untuk memperoleh font sistem asli pada Windows.
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak tersedia');
  final image =
      // ignore: deprecated_member_use
      await layer.toImage(tester.binding.renderView.paintBounds, pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal');
  final directory = Directory(_outputDir)..createSync(recursive: true);
  File('${directory.path}\\$nama.png')
      .writeAsBytesSync(data.buffer.asUint8List(), flush: true);
}
