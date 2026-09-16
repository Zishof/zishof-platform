import 'dart:convert';
import 'dart:io';
import 'package:core_db/core_db.dart';
import 'package:ebisnis/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('HPP server tetap ada setelah katalog melewati cache lokal', () {
    final server = <String, dynamic>{
      'id': 198,
      'kode': 'AN000198',
      'nama': 'Adem Sari',
      'hargaJual': 7000,
      'hargaBeli': 4250,
      'stok': 2,
      'hargaBeliManual': true,
      'bahanBaku': <Map<String, dynamic>>[],
      'satuanId': 3,
      'satuanNama': 'Botol',
    };
    final lokal =
        Produk.fromJson(Produk.cacheRowKeJson(Produk.baseKeCacheRow(server)));
    expect(lokal.hargaBeli, 4250);
    expect(lokal.hargaBeliManual, isTrue);
    expect(lokal.satuanId, 3);
    expect(lokal.stok, 2);
  });

  test('cache lama berbeda dari HPP nol yang sah', () {
    final lama =
        Produk.fromJson(Produk.cacheRowKeJson({'id': 1, 'harga_jual': 7000}));
    expect(lama.hargaBeliTersedia, isFalse);
    final nol = Produk.fromJson(Produk.cacheRowKeJson(
        Produk.baseKeCacheRow({'id': 1, 'hargaBeli': 0})));
    expect(nol.hargaBeliTersedia, isTrue);
    expect(nol.hargaBeli, 0);
  });

  test(
      'HPP dan stok tersimpan atomik dengan outbox, tahan refresh serta restart',
      () async {
    final root = await Directory.systemTemp.createTemp('uat-hpp-cache-');
    const provider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, (_) async => root.path);
    CoreDb.configureStorage('uat_hpp_cache');
    addTearDown(() async {
      await CoreDb.instance.tutup();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(provider, null);
      await root.delete(recursive: true);
    });
    final db = CoreDb.instance;
    final server = Produk.baseKeCacheRow({
      'id': 198,
      'nama': 'Adem Sari',
      'hargaBeli': 4250,
      'hargaJual': 7000,
      'stok': 2
    });
    await db.upsertProdukCache([server]);
    Future<Produk> baca() async => Produk.fromJson(
        Produk.cacheRowKeJson((await db.produkCacheMaster(limit: 10)).single));
    expect((await baca()).hargaBeli, 4250);
    final payload = jsonEncode({
      'id': 198,
      'harga_beli': 4500,
      'harga_beli_manual': true,
      'stok': 7,
      'client_mutation_id': 'uji-hpp-1'
    });
    final id = await db.outboxMasterTambahDenganStokLokal(
        'produk_simpan', 'produk:198', payload,
        produkId: 198, stokFisik: 7);
    expect((await baca()).hargaBeli, 4500);
    expect((await baca()).stok, 7);
    expect(
        jsonDecode((await db.outboxMasterDenganId(id))!['payload_json']
            as String)['harga_beli'],
        4500);
    await db.tutup();
    expect((await baca()).hargaBeli, 4500);
    await db.replaceProdukCache([server]);
    expect((await baca()).hargaBeli, 4500);
    expect((await baca()).stok, 7);
    await db.outboxMasterTandaiGagal(id, 'simulasi server menolak');
    await db.upsertProdukCache([server]);
    expect((await baca()).hargaBeli, 4500);
    expect((await baca()).stok, 7);
    final edit = jsonEncode(
        {'id': 198, 'harga_beli': 4600, 'client_mutation_id': 'uji-hpp-2'});
    final id2 =
        await db.outboxMasterTambah('produk_simpan', 'produk:198', edit);
    expect((await baca()).hargaBeli, 4600);
    expect(await db.outboxMasterPending(), hasLength(1));
    await db.outboxMasterTandaiSukses(id2);
    await db.upsertProdukCache([
      Produk.baseKeCacheRow({'id': 198, 'nama': 'Adem Sari Baru', 'stok': 7})
    ]);
    expect((await baca()).hargaBeli, 4600,
        reason: 'refresh parsial tanpa HPP tidak menghapusnya');
    await db.upsertProdukCache([
      Produk.baseKeCacheRow(
          {'id': 198, 'nama': 'Adem Sari', 'hargaBeli': 0, 'stok': 7})
    ]);
    expect((await baca()).hargaBeli, 0,
        reason: 'angka nol eksplisit dari server tetap dihormati');

    // Simulasikan skema versi 20 pada DB sementara milik tes, bukan data toko.
    final sqlite = await db.db;
    await sqlite.execute('ALTER TABLE produk_cache DROP COLUMN detail_json');
    await sqlite.execute('PRAGMA user_version = 20');
    await db.tutup();
    expect((await baca()).hargaBeliTersedia, isFalse);
    expect((await baca()).stok, 7);
    expect(
        (await (await db.db).rawQuery('PRAGMA user_version'))
            .single
            .values
            .single,
        21);
  });
}
