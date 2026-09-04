import 'package:ebisnis/features/apotik/clinical/apotik_pasien_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _pasien(int jumlah) => List.generate(jumlah, (i) {
      final n = i + 1;
      return {
        'id': n,
        'kode': 'APT-UAT-${n.toString().padLeft(3, '0')}',
        'nama': 'Pasien Demo ${n.toString().padLeft(3, '0')}',
        'jenisKelamin': n.isEven ? 'P' : 'L',
        'tanggalLahir': '1990-01-01',
      };
    });

Future<void> _pump(WidgetTester tester, ApotikPasienPage page) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('memuat 100 pasien tanpa membangun seluruh baris sekaligus',
      (tester) async {
    final data = _pasien(100);
    await _pump(
      tester,
      ApotikPasienPage(
        muatDaftar: (aksi, body, cacheKey, {required onData}) async {
          expect(aksi, 'apotik_pasien_cari');
          expect(body['page_size'], 100);
          onData({'status': 'success', 'data': data, 'dariServer': true});
        },
        panggil: (_, __) async => const {'status': 'success'},
      ),
    );
    expect(find.text('100 pasien'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(100));
    expect(find.text('Pasien Demo 001'), findsOneWidget);
  });

  testWidgets('menampilkan alergi aktif dan riwayat klinis SIRS',
      (tester) async {
    final data = _pasien(1);
    await _pump(
      tester,
      ApotikPasienPage(
        muatDaftar: (_, __, ___, {required onData}) async {
          onData({'status': 'success', 'data': data, 'dariServer': true});
        },
        panggil: (aksi, body) async {
          expect(aksi, 'apotik_pasien_detail');
          expect(body['id'], 1);
          return {
            'status': 'success',
            'data': {
              ...data.first,
              'noHp': '081234567890',
              'alergi': [
                {
                  'substansi': 'Amoxicillin',
                  'reaksi': 'Sesak napas',
                  'keparahan': 'BERAT',
                  'statusKlinis': 'AKTIF',
                  'tanggalCatat': '2026-09-05',
                }
              ],
              'diagnosa': [
                {
                  'kode': 'DX-001',
                  'tanggal': '2026-09-05',
                  'kesimpulan': 'Infeksi saluran pernapasan',
                }
              ],
            },
          };
        },
      ),
    );
    await tester.tap(find.text('Pasien Demo 001'));
    await tester.pumpAndSettle();
    expect(find.text('1 alergi aktif'), findsOneWidget);
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.textContaining('Sesak napas'), findsOneWidget);
    expect(find.text('Infeksi saluran pernapasan'), findsOneWidget);
  });
}
