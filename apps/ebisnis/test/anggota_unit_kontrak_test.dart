import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unit member diterima dari server dan tetap terbawa pada cache offline', () {
    final model = File('lib/models.dart').readAsStringSync();
    final database =
        File('../../packages/core_db/lib/core_db.dart').readAsStringSync();

    expect(model, contains("j['unit'] ?? j['unitNama']"));
    expect(model, contains("b['unit'] ?? ''"));
    expect(model, contains("'unit': j['unit'] ?? j['unitNama']"));
    expect(database, contains("'unit TEXT'"));
    expect(database, contains("COALESCE(unit,\\'\\') LIKE ?"));
    expect(database, contains('versiLama < 21'));
  });

  test('Unit tampil pada daftar, topup, dan saldo voucher', () {
    final member = File('lib/screens/anggota/tab_data_member.dart')
        .readAsStringSync();
    final topup = File('lib/screens/anggota/tab_topup.dart').readAsStringSync();
    final voucher =
        File('lib/screens/anggota/tab_saldo_voucher.dart').readAsStringSync();

    expect(member, contains("AppTableColumn('Unit'"));
    expect(member, contains('a.unit.trim()'));
    expect(topup, contains("AppTableColumn('Unit'"));
    expect(voucher, contains("AppTableColumn('Unit'"));
    expect(voucher, contains("DynamicReportColumn('unit', 'Unit')"));
  });
}
