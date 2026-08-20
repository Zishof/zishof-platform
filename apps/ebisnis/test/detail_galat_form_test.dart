import 'package:ebisnis/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penolakan server membawa dua lapis: kalimat untuk pengguna (`message`) dan
/// jejak teknis (`teknis`). Form yang hanya menampilkan lapis pertama membuat
/// alasan penolakan tak terlihat sama sekali -- persis yang terjadi pada dialog
/// Tambah Topup. Uji ini mengunci perilaku penyingkap "Detail Error": tertutup
/// saat muncul, terbuka penuh saat diketuk.
void main() {
  Widget bungkus({String? detail}) => MaterialApp(
        home: Scaffold(
          body: AppFormSheet(
            scrollController: ScrollController(),
            title: 'Tambah Topup',
            icon: Icons.add_card_outlined,
            errorText: 'Jenis keanggotaan member ini tidak diizinkan '
                'menerima topup lewat kasir.',
            errorDetail: detail,
            actions: const [],
            children: const [],
          ),
        ),
      );

  testWidgets('detail error tersembunyi sampai diketuk', (tester) async {
    await tester.pumpWidget(bungkus(detail: 'Referensi API-XYZ\nstatus=91'));

    expect(find.textContaining('tidak diizinkan'), findsOneWidget);
    expect(find.text('Detail Error'), findsOneWidget);
    expect(find.textContaining('API-XYZ'), findsNothing);

    await tester.tap(find.text('Detail Error'));
    await tester.pumpAndSettle();

    expect(find.textContaining('API-XYZ'), findsOneWidget);
    expect(find.text('Salin'), findsOneWidget);
  });

  testWidgets('tanpa detail, penyingkap tidak ditampilkan', (tester) async {
    await tester.pumpWidget(bungkus());

    expect(find.textContaining('tidak diizinkan'), findsOneWidget);
    expect(find.text('Detail Error'), findsNothing);
  });

  testWidgets('detail kosong diperlakukan seperti tanpa detail',
      (tester) async {
    await tester.pumpWidget(bungkus(detail: '   '));

    expect(find.text('Detail Error'), findsNothing);
  });
}
