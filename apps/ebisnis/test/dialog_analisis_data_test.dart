import 'package:ebisnis/widgets/dialog_analisis_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Popup "Analisis Data" merekap baris yang SEDANG TAMPIL. Yang diuji di sini
/// bukan tampilannya, melainkan janji-janji yang membuat rekapnya bisa dipercaya:
/// kolom yang tidak bermakna dilewati DAN disebutkan, kelompok yang tidak muat
/// tetap ikut dijumlahkan, dan laporan kosong tidak menampilkan angka apa pun.
void main() {
  // Bentuk data persis seperti hasil laporan: kolom {l,t}, baris list-per-indeks.
  final kolom = <Map<String, dynamic>>[
    {'l': 'Nota', 't': 'text'},
    {'l': 'Toko', 't': 'text'},
    {'l': 'Metode', 't': 'text'},
    {'l': 'Sisa', 't': 'num'},
  ];
  final baris = <List<dynamic>>[
    ['AB001', 'Toko A', 'Tunai', 1000],
    ['AB002', 'Toko A', 'Tunai', 2000],
    ['AB003', 'Toko B', 'QRIS', 3000],
    ['AB004', 'Toko B', 'Kasbon', 4000],
  ];

  Future<void> buka(WidgetTester t, List<List<dynamic>> data) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: ElevatedButton(
            onPressed: () => tampilkanAnalisisData(c,
                judul: 'Daftar Saldo Piutang', kolom: kolom, baris: data),
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('buka'));
    await t.pumpAndSettle();
  }

  testWidgets('tab dibuat per kolom pengelompokan, bukan per kolom', (t) async {
    await buka(t, baris);
    expect(find.text('Ringkasan'), findsOneWidget);
    expect(find.text('Per Toko'), findsOneWidget);
    expect(find.text('Per Metode'), findsOneWidget);
    // "Nota" unik di tiap baris -- merekapnya tidak menjelaskan apa pun.
    expect(find.text('Per Nota'), findsNothing);
  });

  testWidgets('kolom yang dilewati TETAP disebutkan, bukan dihilangkan diam-diam',
      (t) async {
    await buka(t, baris);
    expect(
      find.textContaining('Kolom yang TIDAK dianalisis'),
      findsOneWidget,
      reason: 'pengguna harus tahu apa yang tidak ikut dihitung',
    );
  });

  testWidgets('ringkasan menghitung jumlah dan banyaknya nilai nol', (t) async {
    await buka(t, [
      ...baris,
      ['AB005', 'Toko A', 'Tunai', 0],
    ]);
    // 1000+2000+3000+4000+0 = 10.000
    expect(find.text('10.000'), findsWidgets);
    expect(find.text('Bernilai 0'), findsOneWidget); // judul kolom ringkasan
  });

  testWidgets('rekap per toko menjumlahkan kolom nilai', (t) async {
    await buka(t, baris);
    await t.tap(find.text('Per Toko'));
    await t.pumpAndSettle();
    expect(find.text('Toko A'), findsOneWidget);
    expect(find.text('Toko B'), findsOneWidget);
    expect(find.text('3.000'), findsWidgets); // Toko A = 1000+2000
    expect(find.text('7.000'), findsWidgets); // Toko B = 3000+4000
    expect(find.text('TOTAL'), findsOneWidget);
  });

  testWidgets('laporan kosong tidak menampilkan angka apa pun', (t) async {
    await buka(t, <List<dynamic>>[]);
    expect(find.textContaining('belum memuat baris'), findsOneWidget);
    // Tanpa baris tidak ada kolom yang layak dikelompokkan, jadi tab rekap pun
    // tidak dibuat -- lebih jujur daripada memajang tab kosong yang mengesankan
    // ada sesuatu untuk dilihat.
    expect(find.text('Per Toko'), findsNothing);
    expect(find.text('TOTAL'), findsNothing); // dan tidak ada angka palsu
  });
}
