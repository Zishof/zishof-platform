import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kartu lanjutan membuka modul operasional khusus', () {
    final source = File(
      'lib/screens/apotik/manajemen_farmasi_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'delivery' => const DeliveryApotikScreen()"));
    expect(source, contains("'membership' => const MembershipApotikScreen()"));
    expect(
      source,
      contains("'analitik' => const RiwayatPenjualanAnalisisScreen()"),
    );
    expect(source, contains("'laporan' => const RiwayatAuditScreen("));
  });

  test('delivery apotik memakai API khusus dan mendukung alur end-to-end', () {
    final source = File(
      'lib/screens/apotik/delivery_apotik_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'apotik_delivery_list'"));
    expect(source, contains("'apotik_delivery_simpan'"));
    expect(source, contains("'apotik_delivery_status'"));
    expect(source, contains("'page_size': 100"));
    expect(source, contains("'TERKIRIM'"));
  });

  test('membership apotik memakai reward ledger dan refill khusus', () {
    final source = File(
      'lib/screens/apotik/membership_apotik_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'apotik_membership_list'"));
    expect(source, contains("'apotik_membership_simpan'"));
    expect(source, contains("'apotik_membership_poin'"));
    expect(source, contains("'apotik_membership_refill'"));
    expect(source, contains("'page_size': 100"));
  });

  test('kartu lanjutan tidak lagi diarahkan ke halaman generik', () {
    final source = File(
      'lib/screens/apotik/manajemen_farmasi_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'resep',\n        'delivery'"));
    expect(source, contains("'pasien',\n        'membership'"));
    expect(source, contains("'penjualan',\n        'analitik'"));
  });
}
