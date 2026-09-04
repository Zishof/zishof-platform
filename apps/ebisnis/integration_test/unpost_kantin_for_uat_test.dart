import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('batalkan posting Kantin sementara untuk bukti praposting',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Capture-Praposting-Kantin',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

    for (final name in const [
      'Penjualan Kantin',
      'Posting HPP',
      'Kulakan Toko',
    ]) {
      try {
        final result = await ApiClient.instance.aksi(
          'draft_jurnal_batal_posting',
          {
            'nama': name,
            'mulai': '2026-09-01',
            'sampai': '2026-09-30',
          },
        );
        // ignore: avoid_print
        print('UNPOST_${name.replaceAll(' ', '_')}=${jsonEncode(result)}');
      } on ApiException catch (error) {
        // Status "tidak ada jurnal" bersifat idempoten; error lain harus tetap
        // terlihat pada log agar bukti praposting tidak menyesatkan.
        if (!error.toString().contains('Tidak ada jurnal')) rethrow;
        // ignore: avoid_print
        print('UNPOST_SKIP_${name.replaceAll(' ', '_')}=$error');
      }
    }
  });
}
