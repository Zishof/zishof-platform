import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audit volume UAT Kantin Pengadaan dan Keuangan', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Audit-Volume',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    final kegagalan = <String>[];

    Future<void> audit(String action, Map<String, dynamic> body) async {
      try {
        final r = await ApiClient.instance.aksi(action, body);
        if (r['status'] != null && r['status'] != 'success') {
          kegagalan.add('$action: status=${r['status']} '
              '${r['description'] ?? ''}');
        }
        int length(Object? value) => value is List ? value.length : -1;
        final summary = <String, dynamic>{
          'status': r['status'],
          'description': r['description'],
          'total': r['total'] ?? r['totalData'] ?? r['jumlah'],
          'data': length(r['data']),
          'rows': length(r['rows']),
          'rincian': length(r['rincian']),
          'draft': r['draft'] ?? r['jumlahDraf'],
          'posting': r['posting'] ?? r['jumlahSiap'],
          'keys': r.keys.take(30).toList(),
        };
        if (r['data'] is List && (r['data'] as List).isNotEmpty) {
          summary['sample'] =
              Map<String, dynamic>.from((r['data'] as List).first as Map);
        } else if (r['rows'] is List && (r['rows'] as List).isNotEmpty) {
          summary['sample'] =
              Map<String, dynamic>.from((r['rows'] as List).first as Map);
        }
        // ignore: avoid_print
        print('AUDIT_$action=${jsonEncode(summary)}');
      } catch (e) {
        kegagalan.add('$action: $e'
            '${e is ApiException ? ' | ${e.teknis}' : ''}');
        // ignore: avoid_print
        print('AUDIT_GAGAL_$action=$e'
            '${e is ApiException ? '\n${e.teknis}' : ''}');
      }
    }

    const listBody = {
      'page': 1,
      'page_size': 500,
      'limit': 500,
      'mulai': '2026-01-01',
      'sampai': '2026-12-31',
    };
    for (final action in [
      'laporan_order_list',
      'kulakan_faktur_list',
      'pengadaan_pr_daftar',
      'pengadaan_po_daftar',
      'pengadaan_bast_daftar',
      'pengadaan_tagihan_daftar',
      'pengadaan_bayar_daftar',
      'uang_muka_daftar',
      'pj_uang_muka_daftar',
      'kas_besar_daftar',
      'pj_kas_besar_daftar',
      'kas_kecil_daftar',
      'penggantian_kas_kecil_daftar',
      'dana_talangan_daftar',
      'reimbursement_daftar',
      'proses_transfer_daftar',
    ]) {
      await audit(action, listBody);
    }
    for (final kind in ['kulakan', 'bayar_hutang', 'terima_piutang']) {
      await audit('posting_${kind}_draft', {
        'mulai': '2026-01-01',
        'sampai': '2026-12-31',
      });
    }
    for (final kind in ['hpp', 'penjualan']) {
      await audit('laporan_keuangan_pendukung', {
        'jenis': kind,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'posting': false,
      });
    }
    await audit('draft_jurnal_ringkasan', {
      'mulai': '2026-01-01',
      'sampai': '2026-12-31',
    });
    for (final name in ['Uang Muka', 'Pertanggungjawaban Uang Muka']) {
      await audit('draft_jurnal_rincian', {
        'nama': name,
        'status': 'draft',
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'limit': 100,
      });
    }
    await audit('pengadaan_pr_barang_tersedia', const {'limit': 20});
    await audit('pengadaan_po_daftar',
        const {'status': 'DISETUJUI', 'page': 1, 'page_size': 20});
    await audit('pengadaan_penyedia_cari', const {'keyword': 'CV'});
    await audit('pengadaan_barang_cari', const {'keyword': 'Bimoli'});
    await audit('katalog', const {'keyword': 'Bimoli', 'tokoId': 1});
    await audit('cara_bayar_list_admin',
        const {'keyword': 'Tunai', 'page': 1, 'page_size': 20});
    await audit('laporan_order_list', const {
      'tglMulai': '2026-01-01',
      'tglSampai': '2026-12-31',
      'page': 1,
      'pageSize': 500,
    });
    for (final kind in ['hpp', 'penjualan']) {
      await audit('laporan_keuangan_pendukung', {
        'jenis': kind,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'posting': false,
      });
    }
    expect(kegagalan, isEmpty,
        reason: 'Seluruh endpoint UAT wajib lulus:\n${kegagalan.join('\n')}');
  });
}
