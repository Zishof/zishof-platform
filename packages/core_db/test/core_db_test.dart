import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CoreDb.instance singleton stabil', () {
    expect(CoreDb.instance, same(CoreDb.instance));
  });

  test(
      'UAT transaksi dipulihkan, disimpan lokal, dan tetap diarsipkan sesudah sinkron',
      () async {
    final root = await Directory.systemTemp.createTemp('ebisnis-core-db-uat-');
    final support = Directory('${root.path}${Platform.pathSeparator}support');
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    await support.create(recursive: true);
    final backupDirectory = Directory(
        '${documents.path}${Platform.pathSeparator}eBisnis${Platform.pathSeparator}Backup');
    await backupDirectory.create(recursive: true);

    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });

    final backup = File(
        '${backupDirectory.path}${Platform.pathSeparator}transaksi-pos-backup.jsonl');
    final payloadPulih = jsonEncode(<String, Object?>{
      'kodeUnik': 'UAT-PULIH-001',
      'kasir': 'uat-kasir',
      'idToko': 1,
      'total': 12500,
      'waktu': '17-08-2026 20:00:00',
      'transaksi': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'nama': 'Produk UAT',
          'jumlah': 1,
          'harga': 12500
        }
      ],
    });
    await backup.writeAsString('${jsonEncode(<String, Object?>{
          'versi': 1,
          'kode_unik': 'UAT-PULIH-001',
          'payload_json': payloadPulih,
          'status': 'PENDING',
          'dibuat_pada': '2026-08-17T20:00:00',
          'akun_kunci': 'uat-kasir',
          'toko_id': 1,
          'id_perangkat': 'uat-device',
          'percobaan': 0,
        })}\n');

    final pulih = await CoreDb.instance
        .transaksiArsipLokal(akunKunci: 'uat-kasir', tokoId: 1);
    expect(pulih.any((row) => row['kode_unik'] == 'UAT-PULIH-001'), isTrue,
        reason: 'backup di luar DB harus membangun ulang arsip SQLite');

    final payloadBaru = jsonEncode(<String, Object?>{
      'kodeUnik': 'UAT-BARU-002',
      'kasir': 'uat-kasir',
      'idToko': 1,
      'total': 25000,
      'waktu': '17-08-2026 20:01:00',
      'transaksi': <Map<String, Object?>>[
        <String, Object?>{
          'id': 2,
          'nama': 'Produk Baru',
          'jumlah': 2,
          'harga': 12500
        }
      ],
    });
    await CoreDb.instance.simpanTransaksiPending(
      'UAT-BARU-002',
      payloadBaru,
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    await CoreDb.instance.tandaiTransaksiSinkron('UAT-BARU-002');

    final arsip = await CoreDb.instance
        .transaksiArsipLokal(akunKunci: 'uat-kasir', tokoId: 1);
    final baru = arsip.firstWhere((row) => row['kode_unik'] == 'UAT-BARU-002');
    expect(baru['status'], 'SYNCED');
    expect(baru['disinkronkan_pada'], isNotNull);
    expect(await backup.readAsLines(), hasLength(greaterThanOrEqualTo(3)),
        reason:
            'backup append-only harus menyimpan snapshot pending dan synced');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Handle SQLite FFI masih hidup sampai proses test berakhir di Windows.
    }
  });
}
