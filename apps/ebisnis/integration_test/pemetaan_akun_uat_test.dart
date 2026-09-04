import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pratinjau/terapkan pemetaan akun laporan UAT', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const terapkan = bool.fromEnvironment('POS_APPLY_ACCOUNT_MAPPING');

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Pemetaan-Akun',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    final aksi = terapkan ? 'pemetaan_akun_terapkan' : 'pemetaan_akun_usulan';
    final hasil = await ApiClient.instance.aksi(aksi, {'batasContoh': 30});
    // ignore: avoid_print
    print('UAT_PEMETAAN_AKUN=${jsonEncode(hasil)}');
    expect('${hasil['status']}', anyOf('00', 'success'));
  });
}
