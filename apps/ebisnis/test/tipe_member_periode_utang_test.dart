import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('form tipe anggota mengirim aturan periode lewat simpan local-first',
      () {
    final source =
        File('lib/screens/anggota/tab_tipe_member.dart').readAsStringSync();
    final awalSimpan = source.indexOf('Future<void> _simpan()');
    final akhirSimpan = source.indexOf('@override', awalSimpan);
    expect(awalSimpan, greaterThanOrEqualTo(0));
    final simpan = source.substring(awalSimpan, akhirSimpan);

    expect(source, contains("String _periodeBatasUtang = 'AKUMULATIF'"));
    expect(source, contains("value: 'AKUMULATIF'"));
    expect(source, contains("value: 'HARIAN'"));
    expect(source, contains("value: 'TIGA_HARI'"));
    expect(source, contains("value: 'MINGGUAN'"));
    expect(source, contains("value: 'BULANAN'"));
    expect(source, contains("value: 'TIGA_BULANAN'"));
    expect(source, contains("value: 'ENAM_BULANAN'"));
    expect(source, contains("value: 'TAHUNAN'"));
    expect(source, contains("value: 'CUSTOM'"));
    expect(simpan, contains("'periodeBatasUtang': _periodeBatasUtang"));
    expect(simpan, contains("'hariCustomBatasUtang': hariCustom ?? 30"));
    expect(simpan, contains('prosesSimpanMaster('));
    expect(simpan, isNot(contains('ApiClient.instance.aksi(')));
  });

  test('jumlah hari khusus dibatasi dan jatah lama tidak dihapus', () {
    final source =
        File('lib/screens/anggota/tab_tipe_member.dart').readAsStringSync();
    expect(source, contains('hariCustom < 1 || hariCustom > 3650'));
    expect(source, contains('Utang lama tetap tercatat dan tetap ditagih.'));
  });
}
