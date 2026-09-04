import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed 50 transaksi POS untuk UAT Kantin', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const volume = int.fromEnvironment('POS_UAT_VOLUME', defaultValue: 1);
    const post = bool.fromEnvironment('POS_UAT_POST');
    const prefix = String.fromEnvironment('POS_UAT_PREFIX',
        defaultValue: 'UAT-VOL-POS-20260904');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Volume-Kantin',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

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
      'keyword': 'ABC Kecap Manis 100 g Botol',
      'tokoId': 1,
    });
    final products = ((catalog['produk'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    expect(products, isNotEmpty);
    final product = products.firstWhere(
      (e) => '${e['nama']}'.contains('ABC Kecap Manis'),
      orElse: () => products.first,
    );
    final price = ((product['hargaJual'] ??
                product['harga'] ??
                product['harga_jual']) as num?)
            ?.toDouble() ??
        25000;
    final payments = await call('cara_bayar_list_admin', {
      'keyword': 'Tunai',
      'page': 1,
      'page_size': 20,
    });
    final payment = ((payments['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .firstWhere((e) => '${e['nama']}'.toLowerCase() == 'tunai');

    final existingReport = await call('laporan_order_list', {
      'tglMulai': '2026-09-01',
      'tglSampai': '2026-09-30',
      'nomorNota': prefix,
      'tokoId': 1,
      'page': 1,
      'pageSize': 100,
    });
    final existingCodes = ((existingReport['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => '${e['kodeUnik'] ?? e['kode'] ?? e['kodeTransaksi']}')
        .toSet();

    int? lastTransactionId;
    for (var i = 1; i <= volume; i++) {
      final code = '$prefix-${i.toString().padLeft(3, '0')}';
      if (existingCodes.contains(code)) {
        if (i == 1 || i % 10 == 0 || i == volume) {
          // ignore: avoid_print
          print('VOLUME_POS_$i=SUDAH_ADA');
        }
        continue;
      }
      final hour = 8 + ((i - 1) ~/ 12);
      final minute = ((i - 1) * 5) % 60;
      final qty = 1 + ((i - 1) % 3);
      final total = price * qty;
      final result = await call('bayar', {
        'kodeUnik': code,
        'clientTrxId': code,
        'idToko': 1,
        'tokoId': 1,
        'kasir': 'admin',
        'waktu':
            '04-09-2026 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
        'caraBayar': payment['id'],
        'caraBayarNama': payment['nama'],
        'total': total,
        'pajak': 0,
        'diskon_faktur_tipe': 'NOMINAL',
        'diskon_faktur_nilai': 0,
        'nama_mesin': 'UAT Volume Kantin',
        'id_perangkat': 'UAT-VOLUME-KANTIN',
        'terlayani': true,
        'langsungTerlayani': true,
        'statusPelayanan': 'TERLAYANI',
        'transaksi': [
          {
            'id': product['id'],
            'kode': product['kode'],
            'nama': product['nama'],
            'harga': price,
            'jumlah': qty,
            'diskon': 0,
            'aturanDiskon': 0,
            'diskon_bebas': false,
            'cashback': 0,
            'ekstra': const [],
          }
        ],
      });
      lastTransactionId = (result['idTransaksi'] ??
          result['pembelianAnggotaKoperasi'] ??
          result['id']) as int?;
      if (i == 1 || i % 10 == 0 || i == volume) {
        // ignore: avoid_print
        print('VOLUME_POS_$i=${jsonEncode({
              'kode': code,
              'idTransaksi': result['idTransaksi'] ??
                  result['pembelianAnggotaKoperasi'] ??
                  result['id'],
              'total': result['total'],
              'status': result['status'],
              'description': result['description'],
              'detailCount': (result['data'] as List?)?.length,
            })}');
      }
    }

    final orders = await call('laporan_order_list', {
      'tglMulai': '2026-09-01',
      'tglSampai': '2026-09-30',
      'tokoId': 1,
      'page': 1,
      'pageSize': 500,
    });
    // ignore: avoid_print
    print('VOLUME_POS_REPORT=${jsonEncode({
          'total': orders['total'],
          'totalNilai': orders['totalNilai'],
          'totalQty': orders['totalQty'],
          'sample': ((orders['data'] as List?) ?? const []).take(2).toList(),
        })}');
    if (lastTransactionId != null) {
      final detail = await call('detail_transaksi', {'id': lastTransactionId});
      final byCode = await call('laporan_order_list', {
        'nomorNota': prefix,
        'tokoId': 1,
        'page': 1,
        'pageSize': 100,
      });
      // ignore: avoid_print
      print('VOLUME_POS_DETAIL=${jsonEncode({
            'id': lastTransactionId,
            'status': detail['status'],
            'waktu': detail['waktu'],
            'kode': detail['kode'],
            'items': (detail['data'] as List?)?.length,
          })}');
      // ignore: avoid_print
      print('VOLUME_POS_BY_CODE=${jsonEncode({
            'total': byCode['total'],
            'sample': ((byCode['data'] as List?) ?? const []).take(2).toList(),
          })}');
    }

    for (final kind in ['hpp', 'penjualan']) {
      final preview = await call('laporan_keuangan_pendukung', {
        'jenis': kind,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'posting': false,
      });
      final data =
          Map<String, dynamic>.from((preview['data'] as Map?) ?? preview);
      // ignore: avoid_print
      print('VOLUME_${kind.toUpperCase()}_PREVIEW=${jsonEncode({
            'keys': data.keys.toList(),
            'count': (data['transaksi'] as List?)?.length ??
                (data['rincian'] as List?)?.length ??
                data['jumlahTransaksi'] ??
                data['jumlah'],
            'total': data['total'],
            'siap': data['siap'],
            'belumDipetakan': data['belumDipetakan'],
            'jumlahTransaksi': data['jumlahTransaksi'],
            'rincianSample':
                ((data['rincian'] as List?) ?? const []).take(2).toList(),
            'jurnalSample':
                ((data['jurnal'] as List?) ?? const []).take(4).toList(),
            'message': data['message'],
          })}');
      if (post) {
        final readyIds = ((data['rincian'] as List?) ?? const [])
            .whereType<Map>()
            .where((e) => e['siap'] == true && e['id'] != null)
            .map((e) => e['id'])
            .toList();
        if (readyIds.isEmpty) {
          // ignore: avoid_print
          print(
              'VOLUME_${kind.toUpperCase()}_POST=DILEWATI_TIDAK_ADA_BARIS_SIAP');
        } else {
          final posted = await call('laporan_keuangan_pendukung', {
            'jenis': kind,
            'mulai': '2026-09-01',
            'sampai': '2026-09-30',
            'posting': true,
            'posting_ids': readyIds,
          });
          // ignore: avoid_print
          print('VOLUME_${kind.toUpperCase()}_POST=${jsonEncode(posted)}');
        }
      }
    }
  });
}
