import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audit data sumber UAT Keuangan', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Audit-Keuangan',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>?> audit(String nama,
        [Map<String, dynamic>? body]) async {
      try {
        final r = await ApiClient.instance.aksi(nama, body ?? const {});
        final ringkas = <String, dynamic>{
          for (final k in r.keys)
            if (!{'token', 'menu', 'permissions'}.contains(k))
              k: r[k] is List
                  ? {
                      'jumlah': (r[k] as List).length,
                      'contoh': (r[k] as List).take(8).toList(),
                    }
                  : r[k],
        };
        // ignore: avoid_print
        print('AUDIT_$nama=${jsonEncode(ringkas)}');
        return r;
      } catch (e) {
        // ignore: avoid_print
        print(
            'AUDIT_$nama=GALAT ${e.toString()}${e is ApiException ? '\n${e.teknis}' : ''}');
        return null;
      }
    }

    const daftar = <String>[
      'uang_muka',
      'pj_uang_muka',
      'kas_besar',
      'pj_kas_besar',
      'kas_kecil',
      'penggantian_kas_kecil',
      'dana_talangan',
      'reimbursement',
    ];
    for (final nama in daftar) {
      await audit('${nama}_opsi');
      await audit('${nama}_daftar', {
        'dari': '2026-01-01',
        'sampai': '2026-12-31',
      });
    }

    final master = await audit('master_keuangan_opsi');
    for (final meta in ((master?['tipe'] as List?) ?? const [])) {
      final tipe = '${(meta as Map)['tipe']}';
      await audit('master_keuangan_daftar', {'tipe': tipe});
    }

    await audit('proses_transfer_opsi');
    await audit('proses_transfer_daftar');
    await audit('proses_transfer_kandidat');
    await audit('nomor_surat_keuangan_opsi');
    await audit('nomor_surat_keuangan_daftar', {'bagian': 'alur'});
    await audit('nomor_surat_keuangan_daftar', {'bagian': 'templat'});
    await audit('pengadaan_pajak_terutang');
    await audit('pengadaan_pajak_daftar');
    await audit('reimbursement_cari_pegawai');
    await audit('nomor_surat_keuangan_templat_daftar');

    await audit('akun_list', {'limit': 5000});
    await audit('draft_jurnal_ringkasan', {
      'mulai': '2026-08-01',
      'sampai': '2026-09-30',
    });
    await audit('jurnal_umum_daftar', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
      'limit': 100,
    });
  });
}
