import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tombol data contoh Apotik memakai gerbang dan generator resmi', () {
    final source = File('lib/screens/apotik/persediaan_apotik_screen.dart')
        .readAsStringSync();

    expect(source, contains('Sesi.instance.bolehDataSample'));
    expect(source, contains("aksi('apotik_provision_demo'"));
    expect(source, contains("'konfirmasi': 'SEED-DEMO-APOTIK'"));
    expect(source, contains("'background': true"));
    expect(source, contains("'status_only': true"));
    expect(source, contains('_pantauProvisionSampaiSelesai'));
    expect(source, contains('_provisionBerhasilKompatibel'));
    expect(source, contains("aksi('apotik_item_cari'"));
    expect(source, contains('_formulariumKey.currentState?.muatUlang()'));
    expect(source, contains("'Data Contoh'"));
  });
}
