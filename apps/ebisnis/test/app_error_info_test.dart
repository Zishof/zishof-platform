import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('informasi teknis error selalu dapat dibuka', (tester) async {
    const info = AppErrorInfo(
      judul: 'Proses belum berhasil',
      pesan: 'Pesan yang mudah dipahami pengguna.',
      solusi: ['Coba kembali.'],
      teknis: 'java.lang.IllegalStateException: contoh stack trace',
      kodeReferensi: 'REQ-123',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppErrorPanel(info: info, ringkas: true)),
    ));

    expect(find.text('Informasi Teknis'), findsOneWidget);
    expect(
        find.textContaining('java.lang.IllegalStateException'), findsNothing);

    await tester.tap(find.text('Informasi Teknis'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kode referensi: REQ-123'), findsOneWidget);
    expect(
        find.textContaining('java.lang.IllegalStateException'), findsOneWidget);
  });
}
