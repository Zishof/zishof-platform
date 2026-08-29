import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';

/// Uji outbox CRUD master offline-first (core_db v10): antre, COALESCE per
/// kunci (edit terakhir yang menang), dan transisi status PENDING ->
/// SYNCED/GAGAL. Bootstrap meniru core_db_test.dart (temp dir + mock
/// path_provider); file test terpisah = proses terpisah, jadi namespace
/// sendiri aman dari singleton CoreDb.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    CoreDb.configureStorage('uat_outbox_master');
    final root =
        await Directory.systemTemp.createTemp('ebisnis-core-db-outbox-');
    final support = Directory('${root.path}${Platform.pathSeparator}support');
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    await support.create(recursive: true);
    await documents.create(recursive: true);
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });
  });

  test('coalesce per kunci: edit berulang menyisakan payload terakhir',
      () async {
    final db = CoreDb.instance;
    expect(await db.jumlahOutboxMasterPending(), 0);

    await db.outboxMasterTambah('produk_simpan', 'produk:1', '{"nama":"A"}');
    await db.outboxMasterTambah('produk_simpan', 'produk:1', '{"nama":"B"}');
    await db.outboxMasterTambah('produk_simpan', 'produk:2', '{"nama":"C"}');
    // Tanpa kunci: tidak pernah di-coalesce (dua draf create berbeda).
    await db.outboxMasterTambah('anggota_simpan', null, '{"nama":"D"}');
    await db.outboxMasterTambah('anggota_simpan', null, '{"nama":"E"}');

    final pending = await db.outboxMasterPending();
    expect(pending.length, 4, reason: 'produk:1 ter-coalesce jadi satu');
    final barisProduk1 =
        pending.where((r) => r['kunci'] == 'produk:1').toList();
    expect(barisProduk1.length, 1);
    expect(barisProduk1.first['payload_json'], '{"nama":"B"}',
        reason: 'edit TERAKHIR yang menang saat replay');
  });

  test('transisi status: sukses & gagal keluar dari antrean pending', () async {
    final db = CoreDb.instance;
    final pending = await db.outboxMasterPending();
    expect(pending, isNotEmpty);

    final idPertama = (pending.first['id'] as num).toInt();
    final idKedua = (pending[1]['id'] as num).toInt();

    await db.outboxMasterCatatPercobaan(idPertama, 'jaringan putus');
    await db.outboxMasterTandaiSukses(idPertama);
    await db.outboxMasterTandaiGagal(idKedua, 'nama sudah terdaftar');

    final sisa = await db.outboxMasterPending();
    expect(sisa.any((r) => r['id'] == idPertama), isFalse);
    expect(sisa.any((r) => r['id'] == idKedua), isFalse);
    expect(await db.jumlahOutboxMasterPending(), pending.length - 2);

    final gagal = await db.outboxMasterGagal();
    expect(gagal.any((r) => r['id'] == idKedua), isTrue,
        reason: 'penolakan bisnis permanen tetap terlihat utk ditindak');
  });

  test('koreksi atas baris GAGAL mengganti payload lama menjadi PENDING',
      () async {
    final db = CoreDb.instance;
    final idLama = await db.outboxMasterTambah(
        'produk_simpan', 'produk:99', '{"nama":"Salah"}');
    await db.outboxMasterTandaiGagal(idLama, 'barcode sudah dipakai');

    final idBaru = await db.outboxMasterTambah(
        'produk_simpan', 'produk:99', '{"nama":"Benar"}');
    final pending = await db.outboxMasterPending();
    final baris = pending.where((r) => r['kunci'] == 'produk:99').toList();
    expect(baris.length, 1);
    expect(baris.single['id'], idBaru);
    expect(baris.single['payload_json'], '{"nama":"Benar"}');
    final gagal = await db.outboxMasterGagal(batas: 500);
    expect(gagal.any((r) => r['id'] == idLama), isFalse,
        reason: 'payload salah tidak boleh hidup berdampingan dgn koreksinya');
  });

  test('refresh katalog server mempertahankan edit produk yang masih pending',
      () async {
    final db = CoreDb.instance;
    await db.replaceProdukCache([
      {
        'id': 501,
        'kode': 'LAMA',
        'barcode': '111',
        'nama': 'Produk server lama',
        'harga_jual': 1000,
        'stok': 2,
        'aktif': 1,
      }
    ]);
    await db.outboxMasterTambah(
      'produk_simpan',
      'produk:501',
      '{"id":501,"kode":"BARU","barcode":"999","nama":"Edit lokal","harga_jual":2500,"aktif":true}',
    );

    // Server masih mengirim versi lama ketika sinkron penuh dijalankan.
    await db.replaceProdukCache([
      {
        'id': 501,
        'kode': 'LAMA',
        'barcode': '111',
        'nama': 'Produk server lama',
        'harga_jual': 1000,
        'stok': 2,
        'aktif': 1,
      }
    ]);

    final hasil = await db.produkCache(keyword: '999');
    expect(hasil, hasLength(1));
    expect(hasil.single['kode'], 'BARU');
    expect(hasil.single['nama'], 'Edit lokal');
    expect(hasil.single['harga_jual'], 2500);
  });
}
