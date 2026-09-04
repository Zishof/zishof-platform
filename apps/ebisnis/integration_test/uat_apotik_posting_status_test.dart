import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.24',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'seluruh posting memiliki 100 draf dan riwayat berstatus eksplisit',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const tokenTersimpan = String.fromEnvironment('POS_TEST_TOKEN');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');

    expect(host, isNotEmpty);
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    if (tokenTersimpan.isNotEmpty) {
      await ApiClient.instance.simpanToken(tokenTersimpan);
    } else {
      expect(username, isNotEmpty);
      expect(password, isNotEmpty);
      final login = await ApiClient.instance.aksi('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-Apotik-Status-Posting',
      });
      await ApiClient.instance.simpanToken('${login['token']}');
    }

    Future<Map<String, dynamic>> call(
            String action, Map<String, dynamic> body) async =>
        Map<String, dynamic>.from(await ApiClient.instance.aksi(action, body));

    List<Map<String, dynamic>> rows(Map<String, dynamic> data, String key) =>
        ((data[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final result = <String, dynamic>{};
    const financial = ['hpp', 'penjualan'];
    const store = ['kulakan', 'bayar_hutang', 'terima_piutang', 'penyesuaian'];

    for (final kind in financial) {
      final response = await call('laporan_keuangan_pendukung', {
        'jenis': kind,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'posting': false,
        'batasRiwayat': 10000,
      });
      final data =
          Map<String, dynamic>.from((response['data'] as Map?) ?? response);
      _verifyPostingContract(kind, data, rows);
      result[kind] = _summary(data, rows);
    }

    for (final kind in store) {
      final data = await call('posting_${kind}_draft', {
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'batasRiwayat': 10000,
      });
      _verifyPostingContract(kind, data, rows);
      result[kind] = _summary(data, rows);
    }

    final summary = <String, dynamic>{
      'periode': '2026-09-01 s.d. 2026-09-30',
      'batasRiwayatDiminta': 10000,
      'posting': result,
      'status': 'PASS',
    };
    final output = Directory(_outputDir)..createSync(recursive: true);
    File('${output.path}\\posting-status-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
      flush: true,
    );
    // ignore: avoid_print
    print('UAT_STATUS_POSTING=${jsonEncode(summary)}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

void _verifyPostingContract(
  String kind,
  Map<String, dynamic> data,
  List<Map<String, dynamic>> Function(Map<String, dynamic>, String) rows,
) {
  expect(data.containsKey('rincianSudahDiposting'), isTrue,
      reason: '$kind harus mengirim riwayat terpisah');
  expect(data['batasRiwayat'], 10000,
      reason: '$kind harus menerima batas 10.000 record');
  final pending = rows(data, 'rincian');
  final posted = rows(data, 'rincianSudahDiposting');
  expect(pending.length, greaterThanOrEqualTo(100),
      reason: '$kind wajib mempunyai minimal 100 record belum diposting');
  expect(posted.length, greaterThanOrEqualTo(100),
      reason: '$kind wajib mempunyai minimal 100 record telah diposting');
  expect(
      pending.every((e) =>
          e['sudahDiposting'] == false &&
          '${e['statusPosting']}'.startsWith('BELUM_DIPOSTING_')),
      isTrue,
      reason: '$kind: status draf harus eksplisit');
  expect(
      posted.every((e) =>
          e['sudahDiposting'] == true &&
          e['statusPosting'] == 'SUDAH_DIPOSTING'),
      isTrue,
      reason: '$kind: status riwayat harus eksplisit');
}

Map<String, dynamic> _summary(
  Map<String, dynamic> data,
  List<Map<String, dynamic>> Function(Map<String, dynamic>, String) rows,
) =>
    {
      'belumDiposting': rows(data, 'rincian').length,
      'telahDiposting': rows(data, 'rincianSudahDiposting').length,
      'siapDiposting': data['jumlahSiapDiposting'] ?? data['jumlahSiap'],
      'batasRiwayat': data['batasRiwayat'],
    };
