import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
  final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
  final screen = File('lib/screens/pengiriman_screen.dart').readAsStringSync();

  const keys = <String>[
    'transfer_antar_lokasi',
    'delivery_order',
    'freight_order',
    'shipment_tracking',
    'proof_of_delivery',
    'penerimaan_transfer_outlet',
    'klaim_distribusi',
    'reverse_logistics',
  ];

  const labels = <String>[
    'Transfer Antar Lokasi',
    'Delivery Order',
    'Freight Order/Rute/Muatan',
    'Shipment & Tracking',
    'Proof of Delivery',
    'Penerimaan Transfer Outlet',
    'Selisih/Kerusakan/Klaim',
    'Retur & Reverse Logistics',
  ];

  test('Desktop dan Android memakai grup dan kunci izin pengiriman yang sama',
      () {
    expect(shell, contains("_GrupMenuShell('Distribusi & Pengiriman'"));
    expect(drawer, contains("label: 'Distribusi & Pengiriman'"));

    for (final key in keys) {
      expect(shell, contains("'$key'"), reason: 'kunci $key hilang di shell');
      expect(drawer, contains("'$key'"), reason: 'kunci $key hilang di drawer');
    }
  });

  test('Seluruh submenu rancangan pengiriman tersedia', () {
    for (final label in labels) {
      expect('$shell\n$drawer', contains(label),
          reason: 'submenu $label belum tersedia');
    }
  });

  test('Layar terhubung ke API persisten dengan kontrak rincian yang sama', () {
    for (final action in <String>[
      'distribusi_list',
      'distribusi_detail',
      'distribusi_simpan',
      'distribusi_status',
    ]) {
      expect(screen, contains("'$action'"), reason: 'aksi $action belum aktif');
    }
    for (final field in <String>[
      "'itemId'",
      "'kode'",
      "'nama'",
      "'qty'",
      "'uom'",
      "'clientMutationId'",
    ]) {
      expect(screen, contains(field), reason: 'field $field belum selaras');
    }
    expect(
        screen, isNot(contains('Layanan pengiriman server belum diaktifkan')));
    expect(screen, isNot(contains('Tidak ada data yang diubah')));
    expect(screen, contains('LayoutBuilder'));
    expect(screen, contains('Wrap('));
  });
}
