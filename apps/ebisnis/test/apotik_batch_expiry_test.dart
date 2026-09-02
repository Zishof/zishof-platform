import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_batch_expiry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PanggilBatch _server({
  List<Map<String, dynamic>>? batch,
  Map<String, dynamic>? hasilUbah,
  List<Map<String, dynamic>>? terkirim,
}) {
  return (aksi, body) async {
    terkirim?.add({'aksi': aksi, ...body});
    switch (aksi) {
      case 'apotik_batch_monitor':
        return {'status': '00', 'data': batch ?? const []};
      case 'apotik_batch_status_ubah':
        return hasilUbah ??
            {'status': '00', 'description': 'Status lot diubah.'};
      default:
        return {'status': '91', 'description': 'Aksi tidak dikenal'};
    }
  };
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1400, 900)}) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran),
      child: SizedBox(width: ukuran.width, height: ukuran.height, child: child),
    ),
  ));
  await tester.pumpAndSettle();
}

String _tanggalDalam(int hari) {
  final d = DateTime.now().add(Duration(days: hari));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('menampilkan lot beserta sisa hari menuju kedaluwarsa',
      (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            panggil: _server(batch: [
          {
            'kadaluarsaId': 1,
            'kode': 'OBT-1',
            'nama': 'Amoxicillin 500 mg',
            'tanggalKadaluarsa': _tanggalDalam(20),
            'sisa': 40,
            'kedaluwarsa': false,
            'lotLayak': true,
          }
        ])));
    expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
    expect(find.textContaining('sisa 40'), findsOneWidget);
    expect(find.textContaining('Near-expiry — 20 hari'), findsOneWidget);
  });

  testWidgets('lot yang sudah lewat ditandai kedaluwarsa', (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            panggil: _server(batch: [
          {
            'kadaluarsaId': 2,
            'nama': 'Obat Basi',
            'tanggalKadaluarsa': _tanggalDalam(-5),
            'sisa': 3,
            'kedaluwarsa': true,
            'lotLayak': true,
          }
        ])));
    expect(find.text('Kedaluwarsa'), findsOneWidget);
  });

  testWidgets('lot ditahan menampilkan alasan dari server', (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            panggil: _server(batch: [
          {
            'kadaluarsaId': 3,
            'nama': 'Obat Karantina',
            'tanggalKadaluarsa': _tanggalDalam(60),
            'sisa': 10,
            'kedaluwarsa': false,
            'lotLayak': false,
            'alasanLot': 'Lot dikarantina',
          }
        ])));
    expect(find.text('Lot dikarantina'), findsOneWidget);
  });

  testWidgets('kosong memberi kalimat menenangkan yang menyebut ambang hari',
      (tester) async {
    await _pump(tester, ApotikBatchExpiryPage(panggil: _server()));
    expect(find.text('Tidak ada batch mendekati kedaluwarsa'), findsOneWidget);
    expect(find.textContaining('90 hari ke depan'), findsOneWidget);
  });

  testWidgets('mengubah ambang hari memuat ulang dengan parameter baru',
      (tester) async {
    final terkirim = <Map<String, dynamic>>[];
    await _pump(
        tester, ApotikBatchExpiryPage(panggil: _server(terkirim: terkirim)));
    await tester.tap(find.text('30 hari'));
    await tester.pumpAndSettle();
    expect(terkirim.last['hari_ke_depan'], 30);
  });

  testWidgets('galat server ditampilkan apa adanya', (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            panggil: (aksi, body) async => {
                  'status': '91',
                  'description': 'Monitor batch dinonaktifkan.'
                }));
    expect(find.text('Monitor batch dinonaktifkan.'), findsOneWidget);
  });

  group('Ubah status lot (IR-02 sisi tulis)', () {
    testWidgets('mengirim status dan alasan ke server', (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikBatchExpiryPage(
              panggil: _server(batch: [
            {
              'kadaluarsaId': 9,
              'nama': 'Obat X',
              'tanggalKadaluarsa': _tanggalDalam(40),
              'sisa': 12,
              'kedaluwarsa': false,
              'lotLayak': true,
            }
          ], terkirim: terkirim)));
      await tester.tap(find.text('Ubah status'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kemasan penyok');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final kirim =
          terkirim.lastWhere((e) => e['aksi'] == 'apotik_batch_status_ubah');
      expect(kirim['kadaluarsa_id'], 9);
      expect(kirim['alasan'], 'Kemasan penyok');
    });

    testWidgets('penolakan "alasan wajib" dari server ditampilkan apa adanya',
        (tester) async {
      await _pump(
          tester,
          ApotikBatchExpiryPage(
              panggil: _server(batch: [
            {
              'kadaluarsaId': 9,
              'nama': 'Obat X',
              'tanggalKadaluarsa': _tanggalDalam(40),
              'sisa': 12,
              'kedaluwarsa': false,
              'lotLayak': true,
            }
          ], hasilUbah: {
            'status': '91',
            'description':
                'Alasan wajib diisi (minimal 5 karakter) saat menahan lot -- penahanan stok harus dapat ditelusuri.'
          })));
      await tester.tap(find.text('Ubah status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alasan wajib diisi'), findsOneWidget);
    });
  });
}
