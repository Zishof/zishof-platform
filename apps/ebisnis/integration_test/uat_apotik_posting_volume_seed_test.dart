import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tokoId = 1;
const _volume = int.fromEnvironment('POS_POSTING_VOLUME', defaultValue: 200);
const _resumeReceivables = bool.fromEnvironment(
  'POS_POSTING_RESUME_RECEIVABLES',
  defaultValue: false,
);
const _productOffset = int.fromEnvironment(
  'POS_POSTING_PRODUCT_OFFSET',
  defaultValue: 0,
);
const _stopAfterHppSource = bool.fromEnvironment(
  'POS_POSTING_STOP_AFTER_HPP_SOURCE',
  defaultValue: false,
);
const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.24',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed volume seluruh sumber posting Apotik', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const tokenTersimpan = String.fromEnvironment('POS_TEST_TOKEN');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(_volume, inInclusiveRange(200, 10000));

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    if (tokenTersimpan.isNotEmpty) {
      await ApiClient.instance.simpanToken(tokenTersimpan);
    } else {
      final login = await ApiClient.instance.aksi('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-Apotik-Posting-Volume',
      });
      await ApiClient.instance.simpanToken('${login['token']}');
    }

    Future<Map<String, dynamic>> call(
        String action, Map<String, dynamic> body) async {
      Object? last;
      for (var attempt = 1; attempt <= 5; attempt++) {
        try {
          return Map<String, dynamic>.from(
              await ApiClient.instance.aksi(action, body));
        } catch (error) {
          last = error;
          if (attempt < 5) {
            await Future<void>.delayed(Duration(milliseconds: attempt * 500));
          }
        }
      }
      throw StateError('$action gagal setelah 5 percobaan: $last');
    }

    List<Map<String, dynamic>> rows(Map<String, dynamic> response,
            {String key = 'data'}) =>
        ((response[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final paymentMethods = await call('cara_bayar_list_admin', {
      'keyword': 'Tunai',
      'page': 1,
      'page_size': 20,
    });
    final payment = rows(paymentMethods).firstWhere(
      (e) => '${e['nama']}'.toLowerCase() == 'tunai',
      orElse: () => rows(paymentMethods).first,
    );

    // Satu produk nyata per baris HPP: Posting HPP memang dirancang per produk,
    // sehingga 200 produk berbeda diperlukan untuk mempertahankan 100 pending
    // setelah 100 baris diposting. produk_simpan bersifat upsert untuk kunci yang
    // sama dan bayar bersifat idempoten melalui kodeUnik/clientTrxId.
    final productIds = <int>[];
    if (_resumeReceivables) {
      for (var page = 1; page <= 10 && productIds.length < _volume; page++) {
        final catalog = await call('katalog', {
          'keyword': 'UAT-APT-MED-13424',
          'semuaToko': true,
          'page': page,
          'page_size': 100,
        });
        final part = ((catalog['produk'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => (e['id'] as num).toInt())
            .toList();
        productIds.addAll(part);
        if (part.length < 100) break;
      }
      expect(productIds.length, greaterThanOrEqualTo(_volume),
          reason:
              'Produk sumber HPP belum lengkap; jalankan seed penuh lebih dulu');
    } else {
      for (var i = 1; i <= _volume; i++) {
        final serial = _productOffset + i;
        final number = serial.toString().padLeft(4, '0');
        final code = 'UAT-APT-MED-13424-$number';
        final product = await call('produk_simpan', {
          'toko_id': _tokoId,
          'kode': code,
          'barcode': '99013424$number',
          'nama': 'Obat Jadi Sample UAT $number',
          'harga_beli': 1000 + serial,
          'harga_jual': 2500 + serial,
          'stok': 1000,
          'keterangan':
              'Data sintetis UAT Apotik v1.34.24; bukan untuk pasien nyata',
          'aktif': true,
          'izinkan_jual_minus_stok': true,
          'jenis_item': 'OBAT_JADI',
        });
        final productId = (product['id'] as num).toInt();
        productIds.add(productId);
        await call('bayar', {
          'kodeUnik': 'UAT-APT-HPP-SRC-13424-$number',
          'clientTrxId': 'UAT-APT-HPP-SRC-13424-$number',
          'idToko': _tokoId,
          'tokoId': _tokoId,
          'kasir': 'admin',
          'waktu': '04-09-2026 12:${(i % 60).toString().padLeft(2, '0')}:00',
          'caraBayar': payment['id'],
          'caraBayarNama': payment['nama'],
          'total': 2500 + serial,
          'pajak': 0,
          'diskon_faktur_tipe': 'NOMINAL',
          'diskon_faktur_nilai': 0,
          'nama_mesin': 'UAT Apotik Posting Volume',
          'id_perangkat': 'UAT-APOTIK-POSTING-VOLUME',
          'terlayani': true,
          'langsungTerlayani': true,
          'statusPelayanan': 'TERLAYANI',
          'transaksi': [
            {
              'id': productId,
              'kode': code,
              'nama': 'Obat Jadi Sample UAT $number',
              'harga': 2500 + serial,
              'jumlah': 1,
              'diskon': 0,
              'aturanDiskon': 0,
              'diskon_bebas': false,
              'cashback': 0,
              'ekstra': const [],
            }
          ],
        });
        if (i == 1 || i % 25 == 0 || i == _volume) {
          // ignore: avoid_print
          print('POSTING_SEED_PRODUK_PENJUALAN=$i/$_volume');
        }
      }

      final mapping = await call('pemetaan_akun_kantin_terapkan', {
        'tokoId': _tokoId,
        'timpa': false,
        'kodeKas': '111.101',
        'kodePiutang': '131.300',
        'kodePersediaan': '151.200',
        'kodeUtang': '310.600',
        'kodePendapatan': '410.900',
        'kodeHpp': '510.900',
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
      });
      // ignore: avoid_print
      print('POSTING_SEED_MAPPING=${jsonEncode(mapping)}');

      if (_stopAfterHppSource) {
        // ignore: avoid_print
        print('POSTING_SEED_HPP_SOURCE_FINAL=${jsonEncode({
              'offset': _productOffset,
              'createdOrReused': productIds.length,
              'status': 'PASS',
            })}');
        return;
      }

      final opnameHistory = await call('so_riwayat', {
        'toko_id': _tokoId,
        'limit': 10000,
      });
      final existingOpnameMarkers = rows(opnameHistory)
          .map((e) => '${e['keterangan'] ?? ''}')
          .where((e) => e.startsWith('UAT-APT-ADJ-13424-'))
          .toSet();
      for (var i = 1; i <= productIds.length; i++) {
        final number = i.toString().padLeft(4, '0');
        final marker = 'UAT-APT-ADJ-13424-$number';
        if (!existingOpnameMarkers.contains(marker)) {
          await call('so_simpan', {
            'toko_id': _tokoId,
            'produk_id': productIds[i - 1],
            'stok_fisik': 900 + (i % 20),
            'keterangan': marker,
          });
        }
        if (i == 1 || i % 25 == 0 || i == _volume) {
          // ignore: avoid_print
          print('POSTING_SEED_PENYESUAIAN=$i/$_volume');
        }
      }

      final suppliers = await call(
          'penyedia_list', {'keyword': 'CV Sumber Pangan Nusantara'});
      final supplier = rows(suppliers)
          .firstWhere((e) => '${e['nama']}' == 'CV Sumber Pangan Nusantara');
      final supplierId = (supplier['id'] as num).toInt();

      final invoices = <Map<String, dynamic>>[];
      for (var page = 1; page <= 10 && invoices.length < _volume; page++) {
        final response = await call('kulakan_faktur_list', {
          'toko_id': _tokoId,
          'keyword': 'UAT-VOL-KUL-20260904',
          'page': page,
          'page_size': 100,
        });
        final part = rows(response);
        invoices.addAll(part);
        if (part.length < 100) break;
      }
      expect(invoices.length, greaterThanOrEqualTo(_volume),
          reason:
              'Jalankan seed_volume_kulakan_test.dart volume 200 lebih dulu');
      for (var i = 0; i < _volume; i++) {
        final invoiceId = (invoices[i]['fakturId'] as num).toInt();
        await call('si_purchase_terms_save', {
          'faktur_id': invoiceId,
          'jenis_pembayaran': 'CREDIT',
          'termin_hari': 30,
          'keterangan': 'Termin vendor data sample UAT Apotik',
        });
      }

      final payableByInvoice = <int, Map<String, dynamic>>{};
      for (var page = 1;
          page <= 10 && payableByInvoice.length < _volume;
          page++) {
        final response = await call('si_payable_list', {
          'supplier_id': supplierId,
          'tampilkan_lunas': true,
          'page': page,
          'page_size': 100,
        });
        final part = rows(response);
        for (final payable in part) {
          payableByInvoice[(payable['fakturId'] as num).toInt()] = payable;
        }
        if (part.length < 100) break;
      }
      var payableHandled = 0;
      for (var i = 1; i <= _volume; i++) {
        final invoice = invoices[i - 1];
        final invoiceId = (invoice['fakturId'] as num).toInt();
        final payable = payableByInvoice[invoiceId];
        if (payable == null) {
          throw StateError(
              'Hutang faktur $invoiceId tidak ditemukan setelah termin disimpan.');
        }
        final outstanding = (payable['outstanding'] as num?)?.toDouble() ?? 0;
        if (outstanding > 0) {
          await call('si_payable_payment_create', {
            'supplier_id': supplierId,
            'nominal': outstanding,
            'metode': 'TUNAI',
            'no_bg': '',
            'nama_bank': '',
            'keterangan': 'Pembayaran vendor sample UAT Apotik',
            'kode_unik':
                'UAT-APT-PAYABLE-13424-${i.toString().padLeft(4, '0')}',
            'alokasi': [
              {'faktur_id': invoiceId, 'nominal': outstanding}
            ],
          });
        }
        payableHandled++;
        if (i == 1 || i % 25 == 0 || i == _volume) {
          // ignore: avoid_print
          print('POSTING_SEED_BAYAR_HUTANG=$payableHandled/$_volume');
        }
      }
    }

    final orderIds = <int>[];
    orders:
    for (var candidate = 1;
        candidate <= _volume + 100 && orderIds.length < _volume;
        candidate++) {
      final number = candidate.toString().padLeft(4, '0');
      try {
        final order = await call('si_sales_order_create', {
          'toko_id': _tokoId,
          'customer_id': 1,
          'kode_unik': 'UAT-APT-RECEIVABLE-13424-$number',
          'tanggal': '2026-09-04',
          'keterangan': 'Penjualan kredit sample UAT Apotik',
          'items': [
            {
              'produk_id': productIds[(candidate - 1) % productIds.length],
              'jumlah': 1,
              'harga': 5000 + candidate,
            }
          ],
        });
        final orderId = (order['id'] as num).toInt();
        for (var step = 0; step < 5; step++) {
          final detail = await call('si_sales_order_detail', {
            'order_id': orderId,
          });
          final data = Map<String, dynamic>.from(detail['data'] as Map);
          switch ('${data['status']}') {
            case 'DRAFT':
              await call('si_sales_order_status', {
                'order_id': orderId,
                'status': 'PESAN',
              });
            case 'PESAN':
              await call('si_sales_order_status', {
                'order_id': orderId,
                'status': 'SIAP_KIRIM',
              });
            case 'SIAP_KIRIM':
              await call('si_sales_order_status', {
                'order_id': orderId,
                'status': 'TERKIRIM',
              });
            case 'TERKIRIM':
              await call('si_sales_order_invoice', {'order_id': orderId});
            default:
              step = 5;
          }
        }
        orderIds.add(orderId);
      } catch (error) {
        // Respons detail sesekali terpotong di gateway. Dokumen dengan kode
        // unik ini tetap aman dan dapat dilanjutkan pada run berikutnya;
        // kandidat tambahan menjaga volume bukti tetap tepat 200 dokumen.
        // ignore: avoid_print
        print('POSTING_SEED_PIUTANG_SKIP=$number:$error');
        continue orders;
      }
      final selesai = orderIds.length;
      if (selesai == 1 || selesai % 25 == 0 || selesai == _volume) {
        // ignore: avoid_print
        print('POSTING_SEED_PIUTANG_INVOICE=$selesai/$_volume');
      }
    }
    expect(orderIds.length, _volume,
        reason: 'Harus tersedia tepat $_volume invoice piutang yang berhasil');

    final receivables = <Map<String, dynamic>>[];
    for (var page = 1; page <= 20 && receivables.length < _volume; page++) {
      final response = await call('si_receivable_list', {
        'customer_id': 1,
        'tampilkan_lunas': true,
        'page': page,
        'page_size': 100,
      });
      final part = rows(response, key: 'rows');
      receivables.addAll(part);
      if (part.length < 100) break;
    }
    final byOrder = <int, Map<String, dynamic>>{
      for (final row in receivables)
        if (row['orderId'] is num) (row['orderId'] as num).toInt(): row,
    };
    expect(orderIds.every(byOrder.containsKey), isTrue,
        reason: 'Semua invoice penjualan harus muncul sebagai piutang');
    for (var i = 1; i <= orderIds.length; i++) {
      final receivable = byOrder[orderIds[i - 1]]!;
      final outstanding = (receivable['outstanding'] as num).toDouble();
      if (outstanding > 0) {
        await call('si_collection_create', {
          'customer_id': 1,
          'nominal': outstanding,
          'metode': 'TUNAI',
          'keterangan': 'Penerimaan piutang sample UAT Apotik',
          'kode_unik':
              'UAT-APT-COLLECTION-13424-${i.toString().padLeft(4, '0')}',
          'alokasi': [
            {'piutang_id': receivable['id'], 'nominal': outstanding}
          ],
        });
      }
      if (i == 1 || i % 25 == 0 || i == _volume) {
        // ignore: avoid_print
        print('POSTING_SEED_TERIMA_PIUTANG=$i/$_volume');
      }
    }

    Future<Map<String, dynamic>> posting(String kind) async {
      if (kind == 'hpp' || kind == 'penjualan') {
        final response = await call('laporan_keuangan_pendukung', {
          'jenis': kind,
          'mulai': '2026-09-01',
          'sampai': '2026-09-30',
          'posting': false,
          'batasRiwayat': 10000,
        });
        return Map<String, dynamic>.from(
            (response['data'] as Map?) ?? response);
      }
      return call('posting_${kind}_draft', {
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'batasRiwayat': 10000,
      });
    }

    final summary = <String, dynamic>{};
    for (final kind in [
      'hpp',
      'penjualan',
      'kulakan',
      'bayar_hutang',
      'terima_piutang',
      'penyesuaian',
    ]) {
      final data = await posting(kind);
      summary[kind] = {
        'belumDiposting': rows(data).length,
        'telahDiposting': rows(data, key: 'rincianSudahDiposting').length,
        'siapDiposting': data['jumlahSiapDiposting'],
      };
    }
    final output = Directory(_outputDir)..createSync(recursive: true);
    File('${output.path}\\posting-seed-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
      flush: true,
    );
    // ignore: avoid_print
    print('POSTING_SEED_FINAL=${jsonEncode(summary)}');
  }, timeout: const Timeout(Duration(hours: 2)));
}
