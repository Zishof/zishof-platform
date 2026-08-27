import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PIN hanya dapat dikelola supervisor/admin dan tidak diekspor asli', () {
    final layar =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    final sesi = File('lib/sesi.dart').readAsStringSync();

    expect(layar, contains('Sesi.instance.bolehKelola'));
    expect(layar, contains("'anggota_pin_simpan_massal'"));
    expect(layar, contains("'PIN_SUDAH_DIATUR'"));
    expect(layar, contains("'PIN_BARU'"));
    expect(layar, contains('PIN asli/hash tidak disertakan'));
    expect(layar, isNot(contains("m['pin']")));
    expect(sesi,
        contains('bool get bolehKelola => isAdmin || supervisorPedagang'));
  });

  test('unggahan PIN tidak masuk outbox local-first', () {
    final layar =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    final blok = layar.substring(
      layar.indexOf('Future<void> _uploadPin()'),
      layar.indexOf('Future<void> _aturPinMember'),
    );

    expect(blok, contains('ApiClient.instance'));
    expect(blok, isNot(contains('prosesSimpanMaster')),
        reason: 'PIN tidak boleh dipersistenkan di outbox perangkat');
    expect(blok, isNot(contains('MasterOffline')));
  });
}
