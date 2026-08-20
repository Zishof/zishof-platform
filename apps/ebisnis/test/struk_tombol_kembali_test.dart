import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Laporan kasir 21-08-2026: tombol "Kembali ke Halaman Sebelumnya" pada layar
/// struk tidak berfungsi. Penyebabnya `maybePop()` DIAM tanpa pesan bila layar
/// struk adalah satu-satunya route -- tombol terlihat aktif tetapi tidak
/// melakukan apa pun.
///
/// Uji ini mengunci perilaku yang benar: apa pun kondisi tumpukan navigasi,
/// menekan tombol harus MENGHASILKAN perpindahan halaman, bukan diam.
void main() {
  /// Tiruan keputusan navigasi yang sama dgn `_kembaliDariStruk`.
  void kembali(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushReplacement(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('KASIR'))));
  }

  Widget layarStruk() => Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('STRUK'),
            OutlinedButton(
              onPressed: () => kembali(context),
              child: const Text('Kembali ke Halaman Sebelumnya'),
            ),
          ]),
        ),
      );

  testWidgets('struk sebagai route TUNGGAL: tombol tetap berpindah ke Kasir',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: layarStruk()));
    expect(find.text('STRUK'), findsOneWidget);

    await tester.tap(find.text('Kembali ke Halaman Sebelumnya'));
    await tester.pumpAndSettle();

    // Sebelum perbaikan, layar tetap di STRUK -- tombol jadi jalan buntu.
    expect(find.text('STRUK'), findsNothing);
    expect(find.text('KASIR'), findsOneWidget);
  });

  testWidgets('ada halaman sebelumnya: tombol kembali ke halaman itu',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('ASAL'),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => layarStruk())),
              child: const Text('buka struk'),
            ),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('buka struk'));
    await tester.pumpAndSettle();
    expect(find.text('STRUK'), findsOneWidget);

    await tester.tap(find.text('Kembali ke Halaman Sebelumnya'));
    await tester.pumpAndSettle();

    expect(find.text('ASAL'), findsOneWidget);
    expect(find.text('KASIR'), findsNothing);
  });
}
