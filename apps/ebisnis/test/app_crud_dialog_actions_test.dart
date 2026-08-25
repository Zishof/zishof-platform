import 'package:ebisnis/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('form CRUD tetap terbuka dan isian utuh ketika simpan gagal',
      (tester) async {
    var percobaan = 0;
    final controller = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Tambah Data'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                actions: [
                  AppCrudDialogActions(
                    onSubmit: () async {
                      percobaan++;
                      return percobaan > 1;
                    },
                  ),
                ],
              ),
            ),
            child: const Text('Buka'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Data yang dipertahankan');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Tambah Data'), findsOneWidget);
    expect(find.text('Data yang dipertahankan'), findsOneWidget);
    expect(find.textContaining('Belum berhasil disimpan'), findsOneWidget);

    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Tambah Data'), findsNothing);
  });
}
