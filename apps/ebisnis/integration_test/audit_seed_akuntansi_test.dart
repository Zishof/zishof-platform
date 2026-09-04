import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audit data sumber UAT Akuntansi', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Audit-Akuntansi',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<void> audit(String nama, [Map<String, dynamic>? body]) async {
      try {
        final r = await ApiClient.instance.aksi(nama, body ?? const {});
        final ringkas = <String, dynamic>{
          for (final k in r.keys)
            if (!{'token', 'menu', 'permissions'}.contains(k))
              k: r[k] is List
                  ? {
                      'jumlah': (r[k] as List).length,
                      'contoh': (r[k] as List)
                          .take(nama == 'akun_list' ? 30 : 5)
                          .toList(),
                    }
                  : r[k],
        };
        // ignore: avoid_print
        print('AUDIT_$nama=${jsonEncode(ringkas)}');
      } catch (e) {
        // ignore: avoid_print
        print(
            'AUDIT_$nama=GALAT ${e.toString()}${e is ApiException ? '\n${e.teknis}' : ''}');
      }
    }

    await audit('akun_list', {'keyword': 'Laba Ditahan', 'limit': 30});
    await audit('akun_list', {'keyword': 'Modal', 'limit': 30});
    await audit('akun_list', {'keyword': 'Kantin', 'limit': 50});
    await audit('akun_list', {'keyword': 'Usaha', 'limit': 50});
    await audit('akun_list', {'keyword': 'Aset Bersih', 'limit': 50});
    await audit('akun_list', {'keyword': 'Penyusutan', 'limit': 50});
    await audit('jurnal_umum_daftar', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-04',
      'cari': 'UAT Sample',
      'limit': 30,
    });
    await audit('jenis_produk_list', {
      'keyword': 'Saus dan Kecap',
      'page': 1,
      'page_size': 100,
      'termasuk_nonaktif': true
    });
    await audit('jenis_produk_list', {
      'keyword': 'Biskuit dan Wafer',
      'page': 1,
      'page_size': 100,
      'termasuk_nonaktif': true
    });
    for (final jenis in ['kulakan', 'bayar_hutang', 'terima_piutang']) {
      await audit('posting_${jenis}_draft', {
        'mulai': '2026-09-01',
        'sampai': '2026-09-04',
      });
    }
    await audit('posting_hpp', {'mulai': '2026-09-01', 'sampai': '2026-09-04'});
    await audit(
        'posting_penjualan', {'mulai': '2026-09-01', 'sampai': '2026-09-04'});
    await audit('saldo_awal_daftar', {});
    await audit('penyesuaian_template_daftar', {});
    await audit('anggaran_item_list', {
      'tahun': 2025,
      'satkerId': 20000025,
      'sumberDanaId': 0,
      'revisi': 1,
      'cari': 'OPS-00',
    });
    await audit('pengadaan_barang_cari', {
      'keyword': 'Beng-Beng Wafer Cokelat 100 g Botol Isi 6',
      'limit': 20,
      'tokoId': 1,
    });
    await audit('pengadaan_barang_cari', {
      'keyword': 'ABC Kecap Manis 100 g Botol',
      'limit': 20,
      'tokoId': 1,
    });
    await audit('kelompok_aset_list', {'keyword': '', 'limit': 200});
  });
}
