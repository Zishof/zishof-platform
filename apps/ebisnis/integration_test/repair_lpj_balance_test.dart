import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repost LPJ kas besar sampel agar jurnal kembali seimbang',
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
      'labelPerangkat': 'UAT-Repair-LPJ-Balance',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>> call(
        String action, Map<String, dynamic> body) async {
      return Map<String, dynamic>.from(
          await ApiClient.instance.aksi(action, body));
    }

    const period = {'mulai': '2026-09-04', 'sampai': '2026-09-04'};
    final before = await call('draft_jurnal_ringkasan', period);
    final categories = ((before['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final target = categories.firstWhere(
      (e) => '${e['kunci']}' == 'pj_kas_besar',
      orElse: () => <String, dynamic>{},
    );
    // ignore: avoid_print
    print('LPJ_BEFORE=${jsonEncode(target)}');
    expect(target, isNotEmpty,
        reason: 'Kategori Pertanggungjawaban Kas Besar harus tersedia.');

    final posted = (target['posting'] as num?)?.toInt() ?? 0;
    if (posted > 0) {
      final cancel = await call('draft_jurnal_batal_posting', {
        'nama': target['nama'],
        ...period,
      });
      // ignore: avoid_print
      print('LPJ_CANCEL=${jsonEncode(cancel)}');
    }

    final post = await call('draft_jurnal_posting', {
      'nama': target['nama'],
      ...period,
    });
    // ignore: avoid_print
    print('LPJ_REPOST=${jsonEncode(post)}');

    final report = await call('laporan_jalankan', {
      'r': 'akn_jurnal',
      'tglMulai': '2026-09-01',
      'tglSampai': '2026-09-30',
    });
    final rows = ((report['baris'] as List?) ?? const [])
        .whereType<List>()
        .map((e) => List<dynamic>.from(e))
        .toList();
    var debit = 0.0;
    var credit = 0.0;
    for (final row in rows) {
      if (row.length < 7) continue;
      debit += _number(row[5]);
      credit += _number(row[6]);
    }
    final balance = {
      'jumlahBaris': rows.length,
      'debet': debit,
      'kredit': credit,
      'selisih': debit - credit,
    };
    // ignore: avoid_print
    print('LPJ_BALANCE=${jsonEncode(balance)}');
    expect((debit - credit).abs(), lessThan(0.005),
        reason: 'Total jurnal periode UAT harus seimbang setelah repost LPJ.');
  });
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll('.', '').replaceAll(',', '.')) ??
      0;
}
