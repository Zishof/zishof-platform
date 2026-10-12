import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_db/core_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('snapshot database penuh valid dan tersimpan di dua folder', () async {
    if (!Platform.isWindows) return;
    CoreDb.configureStorage('uat_backup');
    final root = await Directory.systemTemp.createTemp('ebisnis-db-backup-');
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

    try {
      sqfliteFfiInit();
      final database = await CoreDb.instance.db;
      final synchronous = await database.rawQuery('PRAGMA synchronous');
      expect(synchronous.single.values.first, 2,
          reason: 'commit harus memakai sinkronisasi penuh');
      await CoreDb.instance.simpanTransaksiPending(
        'UAT-BACKUP-001',
        '{"kodeUnik":"UAT-BACKUP-001","total":12500}',
        akunKunci: 'uat-kasir',
        tokoId: 1,
        idPerangkat: 'uat-device',
      );

      final paths = await CoreDb.instance.cadangkanDatabasePenuh(paksa: true);
      expect(paths, hasLength(2));
      expect(paths[0], isNot(paths[1]));
      for (final path in paths) {
        expect(await File(path).exists(), isTrue);
        final snapshot = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
        );
        try {
          final check = await snapshot.rawQuery('PRAGMA quick_check');
          expect(check.single.values.first, 'ok');
          final rows = await snapshot.query('transaksi_pending',
              where: 'kode_unik = ?', whereArgs: <Object?>['UAT-BACKUP-001']);
          expect(rows, hasLength(1));
        } finally {
          await snapshot.close();
        }
      }
    } finally {
      await CoreDb.instance.tutup();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        // Windows may briefly retain a SQLite FFI handle after close.
      }
    }
  });
}
