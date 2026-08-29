import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
  final screen = File('lib/screens/produksi_screen.dart').readAsStringSync();

  const accessKeys = <String>[
    'produksi_bill_of_material',
    'produksi_work_order',
    'produksi_material_issue',
    'produksi_material_return',
    'produksi_production_output',
    'produksi_production_waste',
    'produksi_production_cost',
  ];

  const documentKinds = <String>[
    'bill_of_material',
    'work_order',
    'material_issue',
    'material_return',
    'production_output',
    'production_waste',
    'production_cost',
  ];

  test('shell responsif menyediakan seluruh submenu dan hak akses produksi',
      () {
    expect(shell, contains("_GrupMenuShell('Produksi'"));
    for (final key in accessKeys) {
      expect(shell, contains("'$key'"), reason: 'hak akses $key hilang');
    }
    for (final builder in <String>[
      '_bangunProduksiBom',
      '_bangunProduksiWorkOrder',
      '_bangunProduksiMaterialIssue',
      '_bangunProduksiMaterialReturn',
      '_bangunProduksiOutput',
      '_bangunProduksiWaste',
      '_bangunProduksiCosting',
    ]) {
      expect(shell, contains(builder), reason: 'builder $builder hilang');
    }
  });

  test('layar produksi memakai tujuh jenis dokumen backend yang kanonis', () {
    for (final kind in documentKinds) {
      expect(screen, contains("'$kind'"), reason: 'jenis $kind hilang');
    }
    for (final action in <String>[
      'produksi_list',
      'produksi_detail',
      'produksi_simpan',
      'produksi_status',
    ]) {
      expect(screen, contains("'$action'"), reason: 'aksi $action hilang');
    }
    expect(screen, contains('ApiClient.instance.aksi'));
  });

  test('form produksi mempertahankan rincian bahan dan genealogi', () {
    for (final field in <String>[
      "'baris'",
      "'genealogi'",
      "'clientMutationId'",
      "'qtyRencana'",
      "'qtyAktual'",
      "'biayaBahan'",
      "'biayaTenagaKerja'",
      "'biayaOverhead'",
    ]) {
      expect(screen, contains(field), reason: 'field $field belum tersedia');
    }
    expect(screen, isNot(contains('distribusi_')));
  });
}
