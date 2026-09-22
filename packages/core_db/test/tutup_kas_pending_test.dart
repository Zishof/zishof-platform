import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core_db/core_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('tutup kas menghitung PENDING dan GAGAL milik sendiri sampai ACK server',
      () async {
    final root = await Directory.systemTemp.createTemp('uat-tutup-kas-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    CoreDb.configureStorage('uat_tutup_kas');
    final db = CoreDb.instance;
    final payload = jsonEncode({
      'kodeUnik': 'UJI-1',
      'kasir': 'kasir-uji',
      'idToko': 1,
      'waktu': '21-09-2026 09:26:55',
      'total': 1000
    });
    await db.simpanTransaksiPending('UJI-1', payload,
        akunKunci: 'kasir-uji', tokoId: 1, idPerangkat: 'mesin-uji');
    await db.tandaiTransaksiGagal('UJI-1', 'uji gangguan');
    expect(
        await db.transaksiPendingBelumSinkron(
            akunKunci: 'kasir-uji', tokoId: 1, idPerangkat: 'mesin-uji'),
        isEmpty);
    expect(
        await db.transaksiPendingBelumSinkron(
            akunKunci: 'kasir-uji',
            tokoId: 1,
            idPerangkat: 'mesin-uji',
            jedaRetry: Duration.zero),
        hasLength(1));
    await db.tandaiTransaksiDitolak('UJI-1', 'uji penolakan');
    await db.simpanTransaksiPending('LAIN-AKUN', '{}',
        akunKunci: 'lain', tokoId: 1, idPerangkat: 'mesin-uji');
    await db.simpanTransaksiPending('LAIN-TOKO', '{}',
        akunKunci: 'kasir-uji', tokoId: 2, idPerangkat: 'mesin-uji');
    await db.simpanTransaksiPending('LAIN-MESIN', '{}',
        akunKunci: 'kasir-uji', tokoId: 1, idPerangkat: 'lain');
    await db.tutup();
    Future<int> tertahan() => db.jumlahTransaksiPendingPemilik(
        akunKunci: 'kasir-uji', tokoId: 1, idPerangkat: 'mesin-uji');
    expect(await tertahan(), 1);
    expect(
        (await db.transaksiLokalDenganKode('UJI-1'))!['payload_json'], payload);
    await db.kembalikanTransaksiKeAntrean(['UJI-1']);
    expect(await tertahan(), 1);
    await db.tandaiTransaksiSinkron('UJI-1');
    expect(await tertahan(), 0);
    expect(
        (await db.transaksiLokalDenganKode('UJI-1'))!['payload_json'], payload);
    await db.tutup();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
