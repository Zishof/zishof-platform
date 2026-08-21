import 'package:ebisnis/widgets/pulihkan_terhapus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Jendela pemulihan penghapusan lokal. Pemuat & pemulihnya disuntik supaya
/// perilakunya dapat diuji tanpa SQLite.
void main() {
  Widget bungkus(Widget anak) => MaterialApp(home: Scaffold(body: anak));

  testWidgets('menawarkan baris terhapus dan memulihkannya', (tester) async {
    final tersisa = [
      {'id': 7, 'kode': '111.000', 'nama': 'KAS', '_kunci': 'kode_akun:7'},
      {'id': 8, 'kode': '112.000', 'nama': 'GIRO BANK'},
    ];
    final dipulihkan = <Object>[];

    await tester.pumpWidget(bungkus(DialogPulihkanTerhapus(
      cacheKey: 'master:kode_akun_akun',
      judul: 'Akun Terhapus',
      labelBaris: (b) => '${b['kode']} - ${b['nama']}',
      pemuat: (_) async => List<Map<String, dynamic>>.from(tersisa),
      pemulih: (cacheKey, id, kunci) async {
        dipulihkan.add(id);
        tersisa.removeWhere((e) => e['id'] == id);
        return true;
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('111.000 - KAS'), findsOneWidget);
    expect(find.text('112.000 - GIRO BANK'), findsOneWidget);

    // Ikonnya dipakai sebagai sasaran ketuk: label tombol berada di dalam
    // susunan Row milik TextButton.icon sehingga tidak cocok utk widgetWithText.
    await tester.tap(find.byIcon(Icons.undo).first);
    await tester.pumpAndSettle();

    expect(dipulihkan, [7], reason: 'baris yang ditekan itulah yang dipulihkan');
    expect(find.text('111.000 - KAS'), findsNothing,
        reason: 'baris yang sudah kembali tidak lagi ditawarkan');
    expect(find.text('112.000 - GIRO BANK'), findsOneWidget);
  });

  testWidgets('memberi tahu bila tidak ada yang bisa dipulihkan',
      (tester) async {
    await tester.pumpWidget(bungkus(DialogPulihkanTerhapus(
      cacheKey: 'master:kosong',
      judul: 'Akun Terhapus',
      labelBaris: (b) => '${b['nama']}',
      pemuat: (_) async => const [],
      pemulih: (_, __, ___) async => false,
    )));
    await tester.pumpAndSettle();

    // Penting disebut: penghapusan yang SUDAH terkirim tidak ada di perangkat,
    // pemulihannya lewat AuditTrails server.
    expect(find.textContaining('AuditTrails'), findsOneWidget);
  });

  testWidgets('mengembalikan jumlah baris yang dipulihkan ke layar pemanggil',
      (tester) async {
    var hasil = -1;
    await tester.pumpWidget(bungkus(Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          hasil = await showDialog<int>(
                context: context,
                builder: (_) => DialogPulihkanTerhapus(
                  cacheKey: 'master:kode_akun_akun',
                  judul: 'Akun Terhapus',
                  labelBaris: (b) => '${b['nama']}',
                  pemuat: (_) async => [
                    {'id': 3, 'nama': 'KAS KECIL'}
                  ],
                  pemulih: (_, __, ___) async => true,
                ),
              ) ??
              0;
        },
        child: const Text('buka'),
      );
    })));

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.undo).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Tutup'));
    await tester.pumpAndSettle();

    expect(hasil, 1, reason: 'layar pemanggil perlu tahu daftarnya harus dimuat ulang');
  });
}
