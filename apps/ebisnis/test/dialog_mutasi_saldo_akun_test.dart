import 'dart:io';

import 'package:ebisnis/widgets/dialog_mutasi_saldo_akun.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  test('Kontrak kode_akun_screen.dart: semua angka saldo dapat diklik membuka popup mutasi', () {
    final src = File('lib/screens/kode_akun_screen.dart').readAsStringSync();
    expect(src, contains("import '../widgets/dialog_mutasi_saldo_akun.dart';"));
    expect(src, contains('bukaDialogMutasiSaldoAkun('));
    expect(src, contains('onTap: () => _bukaMutasiSaldo(a)'));
    expect(src, contains("'Rincian mutasi saldo'"));
  });

  testWidgets(
      'DialogMutasiSaldoAkun menampilkan Saldo Awal, Mutasi Debet/Kredit, Saldo Akhir & paging 15/halaman',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final semuaBaris = List.generate(20, (idx) {
      final no = idx + 1;
      final debet = no.isOdd ? 25000.0 : 0.0;
      final kredit = no.isEven ? 10000.0 : 0.0;
      return <String, dynamic>{
        'id': 1000 + no,
        'noUrut': no,
        'tanggal': '2026-11-10',
        'tanggalTampil': '10-11-2026',
        'kode': 'JRN-00$no',
        'akunKode': '1101010301',
        'akunNama': 'Kas Belanja Tunai Toko Al-Bahjah',
        'keterangan': 'Mutasi uji ke-$no',
        'debet': debet,
        'kredit': kredit,
        'saldo': 100000.0 + (no * 7500.0),
      };
    });

    int panggilanTerakhirPage = 0;
    int panggilanTerakhirPageSize = 0;

    Future<Map<String, dynamic>> mockApi(
        String action, Map<String, dynamic> body) async {
      expect(action, equals('kode_akun_mutasi'));
      final page = (body['page'] as int?) ?? 1;
      final pageSize = (body['pageSize'] as int?) ?? 15;
      panggilanTerakhirPage = page;
      panggilanTerakhirPageSize = pageSize;
      final offset = (page - 1) * pageSize;
      final slice = semuaBaris.skip(offset).take(pageSize).toList();
      return <String, dynamic>{
        'status': '00',
        'akunId': 646100001,
        'akunKode': '1101010301',
        'akunNama': 'Kas Belanja Tunai Toko Al-Bahjah',
        'posisi': 'Debet',
        'grupAkun': 'ASET',
        'punyaAnak': false,
        'termasukAnak': false,
        'tglMulai': '2026-11-01',
        'tglSampai': '2026-11-13',
        'tglMulaiTampil': '01-11-2026',
        'tglSampaiTampil': '13-11-2026',
        'saldoAwal': 100000.0,
        'mutasiDebet': 250000.0,
        'mutasiKredit': 100000.0,
        'saldoAkhir': 250000.0,
        'page': page,
        'pageSize': pageSize,
        'total': semuaBaris.length,
        'totalPages': 2,
        'data': slice,
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DialogMutasiSaldoAkun(
            akun: const {
              'id': 646100001,
              'kode': '1101010301',
              'nama': 'Kas Belanja Tunai Toko Al-Bahjah',
              'posisi': 'Debet',
              'grupAkun': 'ASET',
              'saldo': 250000,
            },
            pemanggilApi: mockApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(panggilanTerakhirPage, equals(1));
    expect(panggilanTerakhirPageSize, equals(15));
    expect(find.text('Saldo Awal', skipOffstage: false), findsOneWidget);
    expect(find.text('Mutasi Debet', skipOffstage: false), findsOneWidget);
    expect(find.text('Mutasi Kredit', skipOffstage: false), findsOneWidget);
    expect(find.text('Saldo Akhir', skipOffstage: false), findsOneWidget);
    expect(find.text('SALDO AWAL', skipOffstage: false), findsOneWidget);
    expect(find.text('SALDO AKHIR', skipOffstage: false), findsOneWidget);
    expect(find.text('Cetak PDF'), findsOneWidget);
    expect(find.text('Download Excel'), findsOneWidget);
    expect(find.textContaining('Halaman 1 dari 2'), findsOneWidget);
    expect(find.text('JRN-001', skipOffstage: false), findsOneWidget);
    expect(find.text('JRN-0015', skipOffstage: false), findsOneWidget);
    expect(find.text('JRN-0016', skipOffstage: false), findsNothing);

    // Pindah ke Halaman 2 (sisa 5 baris)
    await tester.tap(find.text('Berikutnya'));
    await tester.pumpAndSettle();

    expect(panggilanTerakhirPage, equals(2));
    expect(find.textContaining('Halaman 2 dari 2'), findsOneWidget);
    expect(find.text('JRN-0016', skipOffstage: false), findsOneWidget);
    expect(find.text('JRN-0020', skipOffstage: false), findsOneWidget);
  });
}
