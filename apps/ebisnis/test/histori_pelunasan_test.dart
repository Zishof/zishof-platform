import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_db/core_db.dart';
import 'package:ebisnis/screens/anggota/histori_pelunasan_screen.dart';
import 'package:ebisnis/screens/anggota/tab_mutasi_hutang.dart';
import 'package:ebisnis/services/histori_pelunasan.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// Rencana uji: kontrak tanggal & validasi nominal (widget), pemisahan
// pembayaran/piutang dan paginasi (SQLite), restart/retry/failure (integrasi),
// cache lintas akun/filter (unit). Tidak mengirim pembayaran ke server toko.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    root = await Directory.systemTemp.createTemp('uat-pelunasan-');
    CoreDb.configureStorage('uat_pelunasan');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, (_) async => root.path);
  });
  tearDownAll(() async {
    await CoreDb.instance.tutup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, null);
    await root.delete(recursive: true); // Hanya direktori baru milik tes.
  });
  tearDown(() => Sesi.instance.reset());

  test('tanggal lampau dan identitas retry tetap tersimpan setelah restart',
      () async {
    final payload = jsonEncode({
      'id_member': 7,
      'nominal': 15000,
      'waktu': '2026-08-31 10:30:00',
      'client_mutation_id': 'uji-pelunasan-tanggal',
    });
    final db = CoreDb.instance;
    final id = await db.outboxMasterTambah(
        'hutang_bayar_simpan', 'hutang_bayar:uji-tanggal', payload);
    await db.tutup();
    expect((await db.outboxMasterDenganId(id))!['payload_json'], payload);
    await db.outboxMasterTambah(
        'hutang_bayar_simpan', 'hutang_bayar:uji-tanggal', payload);
    final pending = (await db.outboxMasterPending())
        .where((r) => r['kunci'] == 'hutang_bayar:uji-tanggal');
    expect(pending, hasLength(1));
    expect(pending.single['payload_json'], payload);
    await db.outboxMasterTandaiSukses(pending.single['id'] as int);
  });

  Map<String, dynamic> bayar(int id) => {
        'barisId': 'C$id',
        'idAnggota': 7,
        'namaAnggota': 'Pelanggan Uji',
        'waktu': '2026-09-${id.toString().padLeft(2, '0')} 10:30:00',
        'bertambah': 0,
        'berkurang': 1000,
        'keterangan': 'Cicilan $id',
      };

  test('histori hanya pelunasan, terurut terbaru, paginasi SQL dan restart',
      () async {
    final result = {
      'data': [
        {'barisId': 'H1123', 'bertambah': 9999},
        for (var i = 1; i <= 25; i++) bayar(i),
      ]
    };
    await HistoriPelunasan.simpan('halaman', result);
    var data = (await HistoriPelunasan.baca('halaman'))!;
    expect(data['total'], 25);
    expect(data['nominal'], 25000);
    expect(data['data'], hasLength(20));
    expect((data['data'] as List).first['barisId'], 'C25');
    data = (await HistoriPelunasan.baca('halaman', halaman: 2))!;
    expect(data['data'], hasLength(5));
    expect((data['data'] as List).last['barisId'], 'C1');
    await CoreDb.instance.tutup();
    expect((await HistoriPelunasan.baca('halaman'))!['total'], 25);
    // Refresh/retry tidak menduplikasi pembayaran.
    await HistoriPelunasan.simpan('halaman', result);
    expect((await HistoriPelunasan.baca('halaman'))!['total'], 25);
    await HistoriPelunasan.simpan('halaman', {
      'data': [bayar(1)]
    });
    expect((await HistoriPelunasan.baca('halaman', halaman: 2))!['halaman'], 1);
    await HistoriPelunasan.simpan('halaman', {'data': []});
    expect((await HistoriPelunasan.baca('halaman'))!['total'], 0);
  });

  test('timeout, respons rusak dan limit server tidak menghapus cache valid',
      () async {
    await HistoriPelunasan.simpan('aman', {
      'data': [bayar(1)]
    });
    await expectLater(
        HistoriPelunasan.segarkan('aman', {},
            pemuat: (_) async => throw TimeoutException('offline')),
        throwsA(isA<TimeoutException>()));
    for (final result in <Map<String, dynamic>>[
      {'data': 'bukan daftar'},
      {
        'data': [
          bayar(2),
          {...bayar(3), 'waktu': null}
        ]
      },
      {
        'data': [bayar(2), bayar(2)]
      },
      {
        'data': [bayar(2)],
        'total': 50
      },
      {
        'data': List.generate(3000, (_) => {'barisId': 'H1'})
      },
    ]) {
      await expectLater(
          HistoriPelunasan.simpan('aman', result), throwsFormatException);
      expect((await HistoriPelunasan.baca('aman'))!['total'], 1);
    }
  });

  test('cache terpisah per akun, toko, tenant, tanggal dan pelanggan',
      () async {
    final filter = {'dari': '2026-09-01', 'sampai': '2026-09-30'};
    final base = kunciHistoriPelunasan(filter);
    await HistoriPelunasan.simpan(base, {
      'data': [bayar(1)]
    });
    final sesi = Sesi.instance;
    sesi.userId = 'lain';
    expect(await HistoriPelunasan.baca(kunciHistoriPelunasan(filter)), isNull);
    sesi.reset();
    sesi.tokoId = 22;
    expect(kunciHistoriPelunasan(filter), isNot(base));
    sesi.reset();
    sesi.tenantId = 4;
    expect(kunciHistoriPelunasan(filter), isNot(base));
    sesi.reset();
    expect(kunciHistoriPelunasan({...filter, 'id_anggota': 7}), isNot(base));
    expect(
        kunciHistoriPelunasan({...filter, 'dari': '2026-09-02'}), isNot(base));
  });

  testWidgets('tanggal bawaan hari ini, tanggal lampau tersimpan di payload',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? payload;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => FormPelunasanPiutang(
                              idAnggotaAwal: 7,
                              namaAnggotaAwal: 'Pelanggan Uji',
                              simpanUntukTest: (body) async {
                                payload = body;
                              },
                            )),
                    child: const Text('Buka'))))));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(
        find.text(
            'Tanggal pembayaran: ${DateFormat('dd/MM/yyyy').format(now)}'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tanggal-pelunasan')));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(DateUtils.isSameDay(picker.lastDate, now), isTrue);
    // Tutup picker dengan tanggal lampau: menguji handler dan payload form,
    // tanpa bergantung pada bahasa tombol kalender Material.
    final tanggal = DateTime(now.year, now.month, now.day - 3);
    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(tanggal);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Tanggal pembayaran: ${DateFormat('dd/MM/yyyy').format(tanggal)}'),
        findsOneWidget);
    for (final nominal in ['', '0', '-1', 'NaN', 'Infinity']) {
      await tester.enterText(find.byType(TextFormField).first, nominal);
      await tester.ensureVisible(find.text('Simpan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(payload, isNull);
      expect(find.text('Nominal wajib diisi'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextFormField).first, '15000');
    await tester.ensureVisible(find.text('Simpan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(payload!['id_member'], 7);
    expect(payload!['nominal'], 15000);
    expect('${payload!['waktu']}',
        startsWith(DateFormat('yyyy-MM-dd').format(tanggal)));
    expect(find.text('Entri Pelunasan Piutang'), findsNothing);
  });

  testWidgets(
      'histori cache tampil sebelum server selesai dan tetap ada saat offline',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final filter = {
      'dari': '2026-09-01',
      'sampai': '2026-09-30',
      'id_anggota': 7
    };
    await tester
        .runAsync(() => HistoriPelunasan.simpan(kunciHistoriPelunasan(filter), {
              'data': [bayar(1)]
            }));
    final response = Completer<Map<String, dynamic>>();
    Map<String, dynamic>? request;
    await tester.pumpWidget(MaterialApp(
        home: HistoriPelunasanScreen(
      dari: DateTime(2026, 9),
      sampai: DateTime(2026, 9, 30),
      idAnggota: 7,
      namaAnggota: 'Pelanggan Uji',
      pemuat: (body) {
        request = body;
        return response.future;
      },
    )));
    // SQLite berjalan pada isolate nyata, beri waktu di luar fake async.
    for (var i = 0; i < 30 && request == null; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(request, filter,
        reason: 'Server baru dipanggil setelah pembacaan SQLite selesai');
    expect(find.textContaining('1 pembayaran • Total'), findsOneWidget);
    response.completeError(TimeoutException('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 pembayaran • Total'), findsOneWidget);
    expect(find.textContaining('Menampilkan salinan lokal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
