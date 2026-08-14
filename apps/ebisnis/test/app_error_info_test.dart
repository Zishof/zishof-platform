import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('penolakan pembayaran mempertahankan pesan aman dari server', () {
    final gagal = ApiException(
      'Stok TELUR AYAM tidak mencukupi untuk jumlah yang diminta.',
      aktivitas: 'bayar',
      kodeReferensi: 'REQ-BAYAR-1',
      teknis: 'Exception server: contoh detail teknis',
    );

    expect(gagal.info.judul, 'Pembayaran belum berhasil');
    expect(gagal.info.pesan,
        'Stok TELUR AYAM tidak mencukupi untuk jumlah yang diminta.');
    expect(gagal.info.teknis, contains('detail teknis'));
    expect(gagal.info.solusi, isNotEmpty);
  });

  testWidgets('informasi teknis error selalu dapat dibuka', (tester) async {
    String? teksTersalin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        teksTersalin = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

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

    await tester.tap(find.text('Salin Informasi Teknis'));
    await tester.pumpAndSettle();

    expect(teksTersalin, contains('Kode referensi: REQ-123'));
    expect(teksTersalin, contains('java.lang.IllegalStateException'));
  });
}
