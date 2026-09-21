import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_db/core_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('detail bertahan setelah restart dan replay snapshot server', () async {
    final root = await Directory.systemTemp.createTemp('produk-cache-detail-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    CoreDb.configureStorage('uat_produk_detail');
    final database = CoreDb.instance;
    final server = <String, Object?>{
      'id': 17, 'nama': 'Produk uji', 'harga_jual': 7000, 'stok': 45,
      'detail_json': jsonEncode({'hargaBeli': 4850, 'satuanId': 2}),
    };
    await database.upsertProdukCache([server]);
    // Simulasikan skema versi 19 pada DB uji saja, lalu buka lewat migrasi resmi.
    final raw = await database.db;
    await raw.execute('ALTER TABLE produk_cache DROP COLUMN detail_json');
    await raw.execute('PRAGMA user_version = 19');
    await database.tutup();
    final legacy = await database.produkCacheResolveByIds([17]);
    expect(legacy.single['stok'], 45);
    expect(legacy.single['detail_json'], isNull);
    await database.upsertProdukCache([server]);
    await database.tutup();
    var rows = await database.produkCacheResolveByIds([17]);
    expect(jsonDecode(rows.single['detail_json'] as String)['hargaBeli'], 4850);
    await database.outboxMasterTambah('produk_simpan', 'produk:17', jsonEncode({
      'id': 17, 'harga_beli': 4900,
      'bahan_baku': [{'produkId': 18, 'qty': 2, 'harga': 2450}],
    }));
    for (var retry = 0; retry < 2; retry++) {
      await database.replaceProdukCache([server]);
      rows = await database.produkCacheResolveByIds([17]);
      final detail = jsonDecode(rows.single['detail_json'] as String);
      expect(detail['hargaBeli'], 4900);
      expect(detail['satuanId'], 2);
      expect(detail['bahanBaku'], hasLength(1));
      expect(await database.outboxMasterPending(), hasLength(1));
    }
    await database.tutup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
