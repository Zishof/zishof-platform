import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    CoreDb.configureStorage('uat_outbox_is_local_first');
    final root = await Directory.systemTemp.createTemp('ebisnis-core-db-is-');
    final support = Directory('${root.path}${Platform.pathSeparator}support');
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    await support.create(recursive: true);
    await documents.create(recursive: true);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });
  });

  test('kode unik yang sama tetap menjadi satu baris pending terbaru',
      () async {
    final db = CoreDb.instance;
    final idPertama = await db.outboxIsTambah(
        'si_expense_create', 'IS-UAT-001', '{"nilai":1000}');
    final idTerbaru = await db.outboxIsTambah(
        'si_expense_create', 'IS-UAT-001', '{"nilai":1500}');

    final pending = await db.outboxIsPending();
    final baris = pending.where((e) => e['kode_unik'] == 'IS-UAT-001').toList();
    expect(baris, hasLength(1));
    expect(baris.single['id'], idTerbaru);
    expect(baris.single['payload_json'], '{"nilai":1500}');
    expect(idTerbaru, isNot(idPertama));
  });

  test('status berhasil mengeluarkan baris dari antrean', () async {
    final db = CoreDb.instance;
    final pending = await db.outboxIsPending();
    expect(pending, isNotEmpty);
    final id = (pending.single['id'] as num).toInt();
    await db.outboxIsTandaiSukses(id);
    expect(await db.outboxIsPending(), isEmpty);
    expect(await db.jumlahOutboxIsPending(), 0);
  });
}
