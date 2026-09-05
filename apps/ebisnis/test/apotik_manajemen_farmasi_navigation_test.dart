import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kartu lanjutan membuka modul operasional khusus', () {
    final source = File(
      'lib/screens/apotik/manajemen_farmasi_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'delivery' => const PengirimanScreen("));
    expect(source, contains('BagianPengiriman.deliveryOrder'));
    expect(source, contains("'membership' => const AnggotaScreen()"));
    expect(
      source,
      contains("'analitik' => const RiwayatPenjualanAnalisisScreen()"),
    );
    expect(source, contains("'laporan' => const RiwayatAuditScreen("));
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
