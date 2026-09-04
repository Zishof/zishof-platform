import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed 50 faktur kulakan untuk UAT Kantin', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const volume = int.fromEnvironment('POS_UAT_VOLUME', defaultValue: 50);
    const post = bool.fromEnvironment('POS_UAT_POST');
    const prefix = String.fromEnvironment('POS_KUL_UAT_PREFIX',
        defaultValue: 'UAT-VOL-KUL-20260904');

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Volume-Kulakan',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>> call(
        String action, Map<String, dynamic> body) async {
      Object? last;
      for (var attempt = 1; attempt <= 4; attempt++) {
        try {
          return Map<String, dynamic>.from(
              await ApiClient.instance.aksi(action, body));
        } catch (e) {
          last = e;
          if (attempt < 4) {
            await Future<void>.delayed(Duration(milliseconds: attempt * 500));
          }
        }
      }
      throw StateError('$action gagal: $last');
    }

    final catalog = await call('katalog', {
      'keyword': 'Beng-Beng Wafer Cokelat 100 g Botol Isi 6',
      'tokoId': 1,
    });
    final products = ((catalog['produk'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    expect(products, isNotEmpty);
    final product = products.firstWhere(
      (e) => '${e['nama']}'.contains('Beng-Beng Wafer'),
      orElse: () => products.first,
    );

    final suppliers =
        await call('penyedia_list', {'keyword': 'CV Sumber Pangan Nusantara'});
    final supplier = ((suppliers['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .firstWhere((e) => '${e['nama']}' == 'CV Sumber Pangan Nusantara');

    var created = 0;
    for (var i = 1; i <= volume; i++) {
      final number = '$prefix-${i.toString().padLeft(3, '0')}';
      final list = await call('kulakan_faktur_list', {
        'keyword': number,
        'page': 1,
        'page_size': 20,
      });
      final exists = ((list['data'] as List?) ?? const [])
          .whereType<Map>()
          .any((e) => '${e['nomorFaktur']}' == number);
      if (exists) continue;
      final qty = 5 + (i % 6);
      final price = 145000 + ((i % 5) * 2500);
      final result = await call('kulakan_faktur_simpan', {
        'toko_id': 1,
        'nomor_faktur': number,
        'tanggal_faktur':
            '2026-09-${(1 + ((i - 1) % 4)).toString().padLeft(2, '0')}T09:00:00',
        'supplier_id': supplier['id'],
        'keterangan': 'Kulakan persediaan kantin sample volume UAT',
        'items': [
          {
            'produk_id': product['id'],
            'qty': qty,
            'harga_beli_satuan': price,
          }
        ],
      });
      final invoiceId = (result['fakturId'] as num).toInt();
      await call('si_purchase_terms_save', {
        'faktur_id': invoiceId,
        'jenis_pembayaran': i.isEven ? 'CREDIT' : 'CASH',
        'termin_hari': i.isEven ? 30 : 0,
        'keterangan': i.isEven
            ? 'Termin supplier 30 hari — sample UAT'
            : 'Pembelian tunai — sample UAT',
      });
      created++;
      if (i == 1 || i % 10 == 0 || i == volume) {
        // ignore: avoid_print
        print('VOLUME_KULAKAN_$i=${jsonEncode({
              'nomor': number,
              'id': invoiceId,
              'qty': qty,
              'harga': price,
            })}');
      }
    }

    final all = await call('kulakan_faktur_list', {
      'keyword': prefix,
      'page': 1,
      'page_size': 100,
    });
    final draft = await call('posting_kulakan_draft', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
    });
    final ready = ((draft['rincian'] as List?) ?? const [])
        .whereType<Map>()
        .where((e) => e['siap'] == true && e['id'] != null)
        .map((e) => e['id'])
        .toList();
    // ignore: avoid_print
    print('VOLUME_KULAKAN_AUDIT=${jsonEncode({
          'createdThisRun': created,
          'listed': all['total'] ?? (all['data'] as List?)?.length,
          'draft': draft['jumlahDraf'] ?? (draft['rincian'] as List?)?.length,
          'ready': draft['jumlahSiap'] ?? ready.length,
          'blockedSample': ((draft['rincian'] as List?) ?? const [])
              .whereType<Map>()
              .where((e) => e['siap'] != true)
              .take(2)
              .toList(),
        })}');
    if (post && ready.isNotEmpty) {
      final result = await call('posting_kulakan_terapkan', {
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'posting_ids': ready,
      });
      // ignore: avoid_print
      print('VOLUME_KULAKAN_POST=${jsonEncode(result)}');
    }
  });
}
