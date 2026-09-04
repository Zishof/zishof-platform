import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tokoId = 1;
const _prefix = 'UAT-VOL-PROC-20260904';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed alur Pengadaan termin dan non-termin volume UAT',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const volume = int.fromEnvironment('PROC_UAT_VOLUME', defaultValue: 2);

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Volume-Pengadaan',
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
            await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }
      throw StateError('$action gagal: $last');
    }

    final suppliers = await call(
        'pengadaan_penyedia_cari', {'keyword': 'Toko ABC', 'limit': 50});
    final supplierRows = ((suppliers['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    expect(supplierRows, isNotEmpty,
        reason: 'Penyedia Pengadaan Toko ABC tidak ditemukan');
    final supplier = supplierRows.first;
    final supplierId = (supplier['id'] ??
        supplier['penyedia_id'] ??
        supplier['penyediaAssetId']) as num;

    final goods = await call('pengadaan_barang_cari', {
      'keyword': 'ABC Kecap Manis 100 g Botol Isi 4',
      'limit': 50,
    });
    final goodRows = ((goods['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['master_asset_id'] != null)
        .toList();
    expect(goodRows, isNotEmpty,
        reason: 'Barang Pengadaan bertaut Master Aset tidak ditemukan');
    final good = goodRows.first;

    final paymentMethods = await call('pengadaan_cara_bayar_opsi', const {});
    final methodRows = ((paymentMethods['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final paymentMethod = methodRows.isEmpty
        ? null
        : methodRows.firstWhere(
            (e) => e['akunId'] != null || e['akun_id'] != null,
            orElse: () => methodRows.first,
          );

    // PNG 1x1 yang sah. Hanya untuk menguji kontrak lampiran pada basis data demo;
    // manual tetap menjelaskan bahwa operasional wajib memakai foto invoice asli.
    const invoicePng =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

    var completed = 0;
    for (var i = 1; i <= volume; i++) {
      final marker = '$_prefix-${i.toString().padLeft(3, '0')}';
      final existing = await call('pengadaan_pr_daftar', {
        'cari': marker,
        'page': 1,
        'pageSize': 100,
      });
      final found = ((existing['data'] as List?) ?? const [])
          .whereType<Map>()
          .where((e) => '${e['keterangan']}'.contains(marker))
          .toList();
      if (found.isNotEmpty) {
        if (i == 1 || i % 10 == 0 || i == volume) {
          // ignore: avoid_print
          print('PROC_$i=SUDAH_ADA');
        }
        continue;
      }

      final termin = i.isEven;
      final quantity = 4 + (i % 5);
      final unitPrice = 145000 + ((i % 4) * 5000);
      final total = quantity * unitPrice;

      final pr = await call('pengadaan_pr_simpan', {
        'toko_id': _tokoId,
        'tanggal': '04-09-2026',
        'keterangan': '$marker — PR bahan baku kantin',
        'tanpaAnggaran': true,
        'detail': [
          {
            'produk_id': good['produk_id'] ?? good['id'],
            'master_asset_id': good['master_asset_id'],
            'jumlah': quantity,
            'hargaBeli': unitPrice,
            'keterangan': 'Persediaan saus dan kecap untuk operasional kantin',
          }
        ],
      });
      final prId = (pr['id'] as num).toInt();
      await call('pengadaan_pr_putusan', {
        'id': prId,
        'toko_id': _tokoId,
        'keputusan': 'SETUJUI',
      });
      final prDetail = await call('pengadaan_pr_detail', {'id': prId});
      final prLines = ((prDetail['detail'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      expect(prLines, isNotEmpty);

      final po = await call('pengadaan_po_simpan', {
        'toko_id': _tokoId,
        'tanggal': '04-09-2026',
        'penyedia_id': supplierId.toInt(),
        'keterangan': '$marker — PO ${termin ? 'termin' : 'non-termin'}',
        'kodeInvoice': 'QTN-${i.toString().padLeft(3, '0')}',
        'catatanKesepakatan': termin
            ? 'Pembayaran satu termin setelah BAST dan invoice diterima.'
            : 'Pembayaran penuh setelah barang dan invoice diverifikasi.',
        'pengirimanPalingLambat': '10-09-2026',
        'dp': 0,
        'byTermin': termin,
        'detail': [
          {
            'produk_id': good['produk_id'] ?? good['id'],
            'master_asset_id': good['master_asset_id'],
            'pr_detail_id':
                prLines.first['id'] ?? prLines.first['pr_detail_id'],
            'jumlah': quantity,
            'hargaBeli': unitPrice,
            'keterangan': 'Barang sesuai PR $prId',
          }
        ],
        if (termin)
          'termin': [
            {
              'key': '$marker-T1',
              'nomor': '1',
              'nama': 'Termin 1 — 100% setelah BAST',
              'penagihan': total,
              'tanggalD': '20-09-2026',
            }
          ],
      });
      final poId = (po['id'] as num).toInt();
      await call('pengadaan_po_putusan', {
        'id': poId,
        'toko_id': _tokoId,
        'keputusan': 'SETUJUI',
      });

      final bastTemplate =
          await call('pengadaan_bast_dari_po', {'po_id': poId});
      final bastLines = ((bastTemplate['detail'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      expect(bastLines, isNotEmpty);
      final terminRows = ((bastTemplate['termin'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final terminKey =
          termin && terminRows.isNotEmpty ? '${terminRows.first['key']}' : '';
      final bast = await call('pengadaan_bast_simpan', {
        'toko_id': _tokoId,
        'po_id': poId,
        if (termin) 'termin_key': terminKey,
        'penyedia_id': supplierId.toInt(),
        'keterangan': '$marker — BAST ${termin ? 'termin' : 'non-termin'}',
        'kurir': 'Armada Vendor Sample',
        'detail': bastLines
            .map((e) => {
                  'produk_id': e['produk_id'],
                  'master_asset_id': e['master_asset_id'],
                  'po_detail_id': e['po_detail_id'],
                  'diterima': e['diterima'],
                  'hargaBeli': e['hargaBeli'],
                  'hargaPotongan': 0,
                  'diskonPersen': 0,
                  'persenPpn': 0,
                  'persenPph': 0,
                  'kondisi': 'Baik, jumlah dan spesifikasi sesuai PO',
                })
            .toList(),
      });
      final bastId = (bast['id'] as num).toInt();
      final approvedBast = await call('pengadaan_bast_putusan', {
        'id': bastId,
        'toko_id': _tokoId,
        'keputusan': 'SETUJUI',
      });

      await call('pengadaan_lampiran_unggah', {
        'bast_id': bastId,
        'toko_id': _tokoId,
        'kunci': 'INVOICE',
        'nama_file': 'invoice-$marker.png',
        'keterangan':
            'Lampiran teknis data sample UAT — ganti dengan invoice asli',
        'file_base64': invoicePng,
      });
      await call('pengadaan_tagihan_terima', {
        'id': bastId,
        'toko_id': _tokoId,
        'kodeTagihan': 'INV-$marker',
        'tanggalTagihan': '04-09-2026',
      });

      final open = await call('pengadaan_bayar_tagihan_terbuka', {
        'penyedia_id': supplierId.toInt(),
        'toko_id': _tokoId,
      });
      final openRows = ((open['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['po_id'] as num?)?.toInt() == poId)
          .toList();
      expect(openRows, isNotEmpty,
          reason: 'Tagihan terbuka untuk PO $poId tidak ditemukan');
      final openLine = openRows.firstWhere(
        (e) => '${e['termin_key'] ?? ''}' == terminKey,
        orElse: () => openRows.first,
      );
      final pay = await call('pengadaan_bayar_simpan', {
        'toko_id': _tokoId,
        'penyedia_id': supplierId.toInt(),
        'judul': '$marker — Pembayaran Vendor',
        'keterangan': termin
            ? 'Pembayaran vendor termin berdasarkan BAST dan invoice.'
            : 'Pembayaran vendor non-termin berdasarkan BAST dan invoice.',
        if (paymentMethod != null)
          'cara_bayar_id': paymentMethod['id'] ?? paymentMethod['caraBayarId'],
        'tanggal': '04-09-2026',
        'tanggalRealisasi': '04-09-2026',
        'detail': [
          {
            'po_id': poId,
            'termin_key': terminKey,
            'dibayar': openLine['sisa'] ?? openLine['dibayar'] ?? total,
            'pinalti': 0,
            'keterangan': 'Lunas sesuai dokumen $marker',
          }
        ],
      });
      final payId = (pay['id'] as num).toInt();
      final approvedPay = await call('pengadaan_bayar_putusan', {
        'id': payId,
        'toko_id': _tokoId,
        'keputusan': 'SETUJUI',
        'ajukanTransfer': false,
      });
      completed++;
      if (i == 1 || i % 10 == 0 || i == volume) {
        // ignore: avoid_print
        print('PROC_$i=${jsonEncode({
              'mode': termin ? 'TERMIN' : 'NON_TERMIN',
              'prId': prId,
              'poId': poId,
              'bastId': bastId,
              'payId': payId,
              'nilai': total,
              'sinkronKulakan': approvedBast['sinkronKulakan'],
              'peringatanBayar': approvedPay['peringatan'],
            })}');
      }
    }

    final counts = <String, dynamic>{'completedThisRun': completed};
    for (final action in [
      'pengadaan_pr_daftar',
      'pengadaan_po_daftar',
      'pengadaan_bast_daftar',
      'pengadaan_tagihan_daftar',
      'pengadaan_bayar_daftar',
    ]) {
      final r = await call(action, {
        'cari': _prefix,
        'page': 1,
        'pageSize': 100,
      });
      counts[action] = r['total'] ?? (r['data'] as List?)?.length;
    }
    final journal = await call('draft_jurnal_ringkasan', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
    });
    counts['draftJurnalTotal'] = journal['total'];
    counts['draftJurnal'] = journal['draft'];
    counts['postingJurnal'] = journal['posting'];
    counts['kategoriBerisi'] = ((journal['data'] as List?) ?? const [])
        .whereType<Map>()
        .where((e) =>
            ((e['draft'] as num?)?.toInt() ?? 0) > 0 ||
            ((e['posting'] as num?)?.toInt() ?? 0) > 0)
        .map((e) => {
              'kunci': e['kunci'],
              'nama': e['nama'],
              'draft': e['draft'],
              'posting': e['posting'],
              'bisaPosting': e['bisaPosting'],
              'bolehPosting': e['bolehPosting'],
            })
        .toList();
    // ignore: avoid_print
    print('PROC_AUDIT=${jsonEncode(counts)}');
  });
}
