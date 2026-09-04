import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('posting kategori jurnal volume yang siap', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const targets =
        String.fromEnvironment('UAT_POST_KEYS', defaultValue: 'penyusutan');
    final wanted = targets
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Posting-Volume',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>> call(
        String action, Map<String, dynamic> body) async {
      return Map<String, dynamic>.from(
          await ApiClient.instance.aksi(action, body));
    }

    final before = await call('draft_jurnal_ringkasan', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
    });
    final categories = ((before['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => wanted.contains('${e['kunci']}'))
        .toList();
    for (final category in categories) {
      if (((category['draft'] as num?)?.toInt() ?? 0) <= 0 ||
          category['bisaPosting'] != true ||
          category['bolehPosting'] == false) {
        continue;
      }
      try {
        final posted = await call('draft_jurnal_posting', {
          'nama': category['nama'],
          'mulai': '2026-09-01',
          'sampai': '2026-09-30',
        });
        // ignore: avoid_print
        print('POST_${category['kunci']}=${jsonEncode(posted)}');
      } catch (e) {
        // Satu kategori yang gagal tidak boleh menahan kategori independen lain.
        // ignore: avoid_print
        print('POST_GAGAL_${category['kunci']}=$e');
      }
    }
    final after = await call('draft_jurnal_ringkasan', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
    });
    final result = ((after['data'] as List?) ?? const [])
        .whereType<Map>()
        .where((e) => wanted.contains('${e['kunci']}'))
        .map((e) => {
              'kunci': e['kunci'],
              'nama': e['nama'],
              'draft': e['draft'],
              'posting': e['posting'],
            })
        .toList();
    // ignore: avoid_print
    print('POST_AUDIT=${jsonEncode(result)}');
  });
}
