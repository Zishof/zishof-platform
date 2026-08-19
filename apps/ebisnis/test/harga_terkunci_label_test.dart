import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/widgets/app_components.dart';

/// Kebijakan ubah harga: ketika akun tidak diberi akses, harga WAJIB tampil
/// sebagai label. Kolom isian yang sekadar di-disable tidak diterima -- kolom
/// spt itu masih terlihat seperti tempat mengetik dan ikut divalidasi, yang
/// di layar Produk memunculkan galat "Wajib > 0" yang tak bisa diperbaiki
/// pengguna.
void main() {
  Widget bungkus(Widget anak) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: anak)));

  testWidgets('harga terkunci tampil sbg teks, tanpa kolom isian sama sekali',
      (tester) async {
    await tester.pumpWidget(bungkus(
      const AppHargaTerkunci(label: 'Harga Jual', nilai: 'Rp 21.500'),
    ));
    await tester.pump();

    expect(find.text('Harga Jual'), findsOneWidget);
    expect(find.text('Rp 21.500'), findsOneWidget);
    // Tidak boleh ada kolom isian dalam bentuk apa pun. Catatan: SelectableText
    // memakai EditableText di dalamnya (supaya angka bisa disalin), jadi yang
    // diperiksa adalah TIDAK ADA yang bisa diketik -- bukan sekadar absennya
    // EditableText.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    for (final e in tester.widgetList<EditableText>(find.byType(EditableText))) {
      expect(e.readOnly, isTrue,
          reason: 'harga terkunci tidak boleh bisa diketik');
    }
    // Ada penanda gembok supaya alasannya kelihatan.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('nilai kosong tetap terbaca sbg strip, bukan kotak kosong',
      (tester) async {
    await tester.pumpWidget(
        bungkus(const AppHargaTerkunci(label: 'Harga Beli', nilai: '')));
    await tester.pump();
    expect(find.text('-'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    for (final e in tester.widgetList<EditableText>(find.byType(EditableText))) {
      expect(e.readOnly, isTrue);
    }
  });

  testWidgets('catatan alasan ikut tampil bila diberikan', (tester) async {
    await tester.pumpWidget(bungkus(AppHargaTerkunci(
      label: 'Harga Beli Satuan',
      nilai: 'Rp 7.000',
      catatan: Sesi.instance.pesanTidakBolehUbahHarga,
    )));
    await tester.pump();
    expect(find.textContaining('tidak boleh mengubah harga'), findsOneWidget);
  });

  test('default kebijakan: semua pengguna boleh mengubah harga', () {
    // Kompatibel mundur -- toko lama tanpa kolom kebijakan tidak boleh
    // mendadak terkunci.
    expect(Sesi.instance.bolehUbahHarga, isTrue);
    expect(Sesi.instance.pesanTidakBolehUbahHarga,
        contains('tidak diberikan akses'));
  });
}
