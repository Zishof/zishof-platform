import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fokus modal awal dikenali sebagai input teks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TextField(autofocus: true),
        ),
      ),
    );
    await tester.pump();

    final konteks = FocusManager.instance.primaryFocus?.context;
    expect(konteksFokusAdalahInputTeks(konteks), isTrue);

    await tester.enterText(find.byType(TextField), '300000');
    expect(find.text('300000'), findsOneWidget);
  });

  test('pencarian produk cocok terhadap nama, kode, dan barcode', () {
    final produk = Produk(
      id: 1,
      kode: 'AB-123',
      barcode: '8991002003004',
      nama: 'Air Mineral Al Bahjah',
      hargaJual: 5000,
      stok: 10,
      kategoriId: 1,
      kategoriNama: 'Minuman',
      gambarUrl: null,
    );

    expect(produkCocokKataKunci(produk, 'mineral'), isTrue);
    expect(produkCocokKataKunci(produk, 'ab-123'), isTrue);
    expect(produkCocokKataKunci(produk, '8991002003004'), isTrue);
    expect(produkCocokKataKunci(produk, 'produk tidak ada'), isFalse);
  });

  test('pencarian POS mengirim lingkup toko dan menolak respons usang', () {
    final sumber = File('lib/screens/kasir_screen.dart').readAsStringSync();
    final rapat = sumber.replaceAll(RegExp(r'\s+'), '');

    expect(rapat, contains("'toko_id':Sesi.instance.idTokoTerpilih"));
    expect(rapat, contains("'semuaToko':true"));
    expect(rapat, contains('finalgenerasiCari=++_generasiCariProduk'));
    expect(rapat, contains('generasiCari!=_generasiCariProduk'));
    expect(rapat, contains('generasiCari==_generasiCariProduk'));
  });
}
