import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _marker = 'UAT Apotik v1.34.22 - pembayaran vendor';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('50 pembayaran vendor diposting ke jurnal sesuai COA terlampir',
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
      'labelPerangkat': 'UAT-Apotik-Vendor-Jurnal',
    });
    await ApiClient.instance.simpanToken('${login['token']}');

    Future<Map<String, dynamic>> call(
            String action, Map<String, dynamic> body) async =>
        Map<String, dynamic>.from(await ApiClient.instance.aksi(action, body));

    List<Map<String, dynamic>> rows(Map<String, dynamic> response) =>
        ((response['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    Future<Map<String, dynamic>> account(String code) async {
      final found =
          rows(await call('akun_list', {'keyword': code, 'limit': 50}))
              .where((e) => '${e['kode']}' == code && e['leaf'] == true)
              .toList();
      expect(found, hasLength(1), reason: 'Akun $code harus unik dan leaf');
      return found.single;
    }

    final cash = await account('111.101');
    final payable = await account('310.500');
    final payments = rows(await call('pengadaan_bayar_daftar', {
      'toko_id': 1,
      'page': 1,
      'pageSize': 100,
    }))
        .where((e) => e['status'] == 'DISETUJUI' && e['caraBayar'] == 'Tunai')
        .take(50)
        .toList();
    expect(payments, hasLength(50));

    final existing = rows(await call('jurnal_umum_list', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
      'cari': _marker,
      'status': '',
    }));
    final byDescription = {
      for (final row in existing) '${row['keterangan']}': row,
    };
    final toPost = <int>[];
    var created = 0;
    for (final payment in payments) {
      final code = '${payment['kode']}';
      final description = '$_marker $code';
      var journal = byDescription[description];
      if (journal == null) {
        final amount = (payment['nilai'] as num).toDouble();
        final made = await call('jurnal_umum_simpan', {
          'tanggal': '2026-09-04',
          'keterangan': description,
          'jenisTransaksiId': 0,
          'baris': [
            {
              'akunId': payable['id'],
              'debet': amount,
              'kredit': 0,
              'keterangan': 'Pelunasan utang vendor $code',
            },
            {
              'akunId': cash['id'],
              'debet': 0,
              'kredit': amount,
              'keterangan': 'Kas keluar pembayaran vendor $code',
            },
          ],
        });
        journal = {'id': made['id'], 'terposting': false};
        created++;
      }
      if (journal['terposting'] != true && journal['id'] is num) {
        toPost.add((journal['id'] as num).toInt());
      }
    }
    if (toPost.isNotEmpty) {
      await call('jurnal_umum_posting', {'ids': toPost});
    }

    final verified = rows(await call('jurnal_umum_list', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
      'cari': _marker,
      'status': 'posting',
    }));
    expect(verified.length, greaterThanOrEqualTo(50));
    expect(verified.take(50).every((e) => e['terposting'] == true), isTrue);

    // ignore: avoid_print
    print('UAT_VENDOR_JURNAL=${jsonEncode({
          'pembayaranDiperiksa': payments.length,
          'jurnalDibuat': created,
          'jurnalDipostingPadaRun': toPost.length,
          'jurnalTerpostingTerverifikasi': verified.length,
          'debet': '310.500 HUTANG VENDOR',
          'kredit': '111.101 KAS YAYASAN',
        })}');
  });
}
