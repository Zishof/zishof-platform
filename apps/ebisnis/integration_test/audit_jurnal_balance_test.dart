import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audit keseimbangan jurnal periode UAT', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Audit-Balance',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

    final result = await ApiClient.instance.aksi('laporan_jalankan', {
      'r': 'akn_jurnal',
      'tglMulai': '2026-09-01',
      'tglSampai': '2026-09-30',
    });
    final rows = ((result['baris'] as List?) ?? const [])
        .whereType<List>()
        .map((e) => List<dynamic>.from(e))
        .toList();
    // ignore: avoid_print
    print('BALANCE_REPORT_META=${jsonEncode({
          'keys': result.keys.toList(),
          'kolom': result['kolom'],
          'jumlah': rows.length,
          'grandTotal': result['grandTotal'],
          'sampleFirst': rows.take(3).toList(),
          'sampleLast': rows.reversed.take(3).toList(),
        })}');

    final byJournal = <String, List<double>>{};
    for (final row in rows) {
      if (row.length < 7) continue;
      final number = '${row[1]}';
      final debit = _number(row[5]);
      final credit = _number(row[6]);
      final totals = byJournal.putIfAbsent(number, () => [0, 0]);
      totals[0] += debit;
      totals[1] += credit;
    }
    final unbalanced = byJournal.entries
        .where((e) => (e.value[0] - e.value[1]).abs() > 0.005)
        .map((e) => {
              'nomor': e.key,
              'debet': e.value[0],
              'kredit': e.value[1],
              'selisih': e.value[0] - e.value[1],
              'baris': rows
                  .where((r) => r.length > 1 && '${r[1]}' == e.key)
                  .toList(),
            })
        .toList();
    // ignore: avoid_print
    print('BALANCE_UNBALANCED=${jsonEncode(unbalanced)}');
    expect(rows.length, greaterThanOrEqualTo(100),
        reason: 'Laporan jurnal UAT wajib memuat minimal 100 baris.');
    expect(byJournal.length, greaterThanOrEqualTo(100),
        reason: 'Periode UAT wajib memuat minimal 100 nomor jurnal.');
    expect(unbalanced, isEmpty,
        reason: 'Semua jurnal UAT wajib memiliki total debet = kredit.');
  });
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll('.', '').replaceAll(',', '.')) ??
      0;
}
