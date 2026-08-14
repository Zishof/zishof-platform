import 'package:ebisnis/widgets/panduan_stok_kosong.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('panduan stok kosong memuat sedikitnya 350 kata', () {
    final kata = panduanStokKosong
        .trim()
        .split(RegExp(r'\s+'))
        .where((bagian) => bagian.isNotEmpty)
        .length;
    expect(kata, greaterThanOrEqualTo(350));
  });

  testWidgets('dialog menampilkan detail barang dan panduan', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => tampilkanPanduanStokKosong(context,
              detail: 'Produk A (sisa 0, diminta 2)'),
          child: const Text('Buka'),
        );
      }),
    ));

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(find.text('Stok tidak mencukupi'), findsOneWidget);
    expect(find.textContaining('Produk A'), findsOneWidget);
    expect(find.text('Saya Mengerti'), findsOneWidget);
  });
}
