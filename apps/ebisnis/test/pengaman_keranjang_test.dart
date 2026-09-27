import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/widgets/pengaman_keranjang.dart';

void main() {
  testWidgets(
      'navigasi ditolak selama keranjang belum disimpan, isi tetap utuh',
      (tester) async {
    final barang = ['UAT-produk'];
    var pindah = 0;
    await tester.pumpWidget(MaterialApp(
        home: PengamanKeranjang(
      adaBarang: () => barang.isNotEmpty,
      child: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () {
                    if (!PengamanKeranjang.cegahKeluar(context)) pindah++;
                  },
                  child: const Text('Keluar')))),
    )));
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(pindah, 0);
    expect(barang, ['UAT-produk']);
    expect(find.text('Keranjang masih berisi barang'), findsOneWidget);
    await tester.tap(find.text('Kembali ke keranjang'));
    await tester.pumpAndSettle();
    barang.clear(); // Tahan/Bayar berhasil mengosongkan keranjang.
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(pindah, 1);
  });
  testWidgets('halaman selain kasir tetap dapat berpindah', (tester) async {
    var dicegah = true;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () =>
                    dicegah = PengamanKeranjang.cegahKeluar(context),
                child: const Text('Menu')))));
    await tester.tap(find.text('Menu'));
    expect(dicegah, false);
  });
}
