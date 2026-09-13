import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('input member tetap lokal-first dan keterbatasan hak dijelaskan', () {
    final source =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    expect(source, contains("aksi: 'anggota_simpan'"));
    expect(source, contains('prosesSimpanMaster('));
    expect(source,
        contains('memerlukan hak Kelola Pelanggan dari admin atau supervisor'));
    expect(source, contains('if (!Sesi.instance.bolehKelola)'));
  });
}
