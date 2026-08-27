import 'dart:io';

import 'package:core_db/core_db.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    CoreDb.configureStorage('uat_statistik_seluruh_tabel');
    final root = await Directory.systemTemp.createTemp('ebisnis-table-audit-');
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

  test('tabel migrasi baru otomatis masuk inventaris tanpa daftar hardcode',
      () async {
    final core = CoreDb.instance;
    final database = await core.db;
    await database.execute('''
      CREATE TABLE tabel_uji_dinamis (
        id INTEGER PRIMARY KEY,
        status TEXT,
        dibuat_pada TEXT
      )
    ''');
    await database.insert('tabel_uji_dinamis', {
      'id': 1,
      'status': 'PENDING',
      'dibuat_pada': '2026-08-27T21:00:00',
    });

    final statistik = await core.statistikSeluruhTabel();
    final baris = statistik.singleWhere((e) => e['nama'] == 'tabel_uji_dinamis',
        orElse: () => <String, Object?>{});
    expect(baris, isNotEmpty);
    expect(baris['jumlah'], 1);
    expect(baris['pending'], 1);
    expect(baris['jumlah_kolom'], 3);
    expect(baris['terbaru'], '2026-08-27T21:00:00');
  });

  test('soft-delete dalam cache referensi dihitung untuk audit', () async {
    await CoreDb.instance.simpanCacheReferensi(
        'master:uat', '[{"id":1,"_dihapus":true},{"id":2}]');
    final statistik = await CoreDb.instance.statistikSeluruhTabel();
    final cache = statistik.singleWhere((e) => e['nama'] == 'cache_referensi');
    expect(cache['terhapus'], 1);
  });

  test('replace member membersihkan baris yang sudah tidak ada di server',
      () async {
    await CoreDb.instance.upsertAnggotaCache([
      {'id': 1, 'kode': 'LAMA', 'nama': 'Member Lama'}
    ]);
    await CoreDb.instance.replaceAnggotaCache([
      {'id': 2, 'kode': 'BARU', 'nama': 'Member Baru'}
    ]);
    final database = await CoreDb.instance.db;
    final rows = await database.query('anggota_cache', orderBy: 'id');
    expect(rows.map((e) => e['id']), [2]);
  });
}
