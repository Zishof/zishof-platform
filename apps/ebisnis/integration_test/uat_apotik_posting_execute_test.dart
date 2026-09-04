import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _target = 100;
const _selectedKinds = String.fromEnvironment(
  'POS_POSTING_KINDS',
  defaultValue: 'hpp,penjualan,kulakan,bayar_hutang,terima_piutang,penyesuaian',
);
const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.24',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('posting 100 dokumen per kategori dan sisakan 100 draf',
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
      'labelPerangkat': 'UAT-Apotik-Posting-Eksekusi',
    });
    await ApiClient.instance.simpanToken('${login['token']}');

    Future<Map<String, dynamic>> call(
        String action, Map<String, dynamic> body) async {
      Object? last;
      for (var attempt = 1; attempt <= 8; attempt++) {
        try {
          return Map<String, dynamic>.from(
              await ApiClient.instance.aksi(action, body));
        } catch (error) {
          last = error;
          if (attempt < 8) {
            await Future<void>.delayed(Duration(milliseconds: attempt * 500));
          }
        }
      }
      throw StateError('$action gagal setelah 8 percobaan: $last');
    }

    List<Map<String, dynamic>> rows(Map<String, dynamic> response,
            {String key = 'rincian'}) =>
        ((response[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    Future<Map<String, dynamic>> load(String kind) async {
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
        'toko_id': 1,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'batasRiwayat': 10000,
      });
    }

    final kinds = _selectedKinds
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Tambahkan pembayaran atas faktur kredit terbaru hanya ketika kategori
    // Bayar Hutang ikut diuji. Run selektif (mis. retest HPP pascadeploy)
    // tidak boleh gagal karena prasyarat kategori lain yang tidak dipilih.
    if (kinds.contains('bayar_hutang')) {
      var payableDraft = await load('bayar_hutang');
      var payableReady = rows(payableDraft)
          .where((e) => e['siap'] == true && e['id'] != null)
          .length;
      if (payableReady < _target * 2) {
        final suppliers = await call(
            'penyedia_list', {'keyword': 'CV Sumber Pangan Nusantara'});
        final supplier = ((suppliers['data'] as List?) ?? const [])
            .whereType<Map>()
            .firstWhere((e) => '${e['nama']}' == 'CV Sumber Pangan Nusantara');
        final supplierId = (supplier['id'] as num).toInt();
        final payable = await call('si_payable_list', {
          'supplier_id': supplierId,
          'tampilkan_lunas': false,
          'page': 1,
          'page_size': 100,
        });
        final outstanding = ((payable['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => ((e['outstanding'] as num?)?.toDouble() ?? 0) > 0)
            .take(_target * 2 - payableReady)
            .toList();
        expect(outstanding.length, _target * 2 - payableReady,
            reason:
                'Faktur kredit outstanding harus cukup untuk 200 pembayaran');
        for (var i = 0; i < outstanding.length; i++) {
          final invoice = outstanding[i];
          final amount = (invoice['outstanding'] as num).toDouble();
          await call('si_payable_payment_create', {
            'supplier_id': supplierId,
            'nominal': amount,
            'metode': 'TUNAI',
            'no_bg': '',
            'nama_bank': '',
            'keterangan': 'Pembayaran vendor tambahan UAT Apotik',
            'kode_unik':
                'UAT-APT-PAYABLE-TOPUP-13424-${(i + 1).toString().padLeft(4, '0')}',
            'alokasi': [
              {'faktur_id': invoice['fakturId'], 'nominal': amount}
            ],
          });
          if (i == 0 || (i + 1) % 25 == 0 || i + 1 == outstanding.length) {
            // ignore: avoid_print
            print('POSTING_TOPUP_BAYAR_HUTANG=${i + 1}/${outstanding.length}');
          }
        }
        payableDraft = await load('bayar_hutang');
        payableReady = rows(payableDraft)
            .where((e) => e['siap'] == true && e['id'] != null)
            .length;
      }
      expect(payableReady, greaterThanOrEqualTo(_target * 2));
    }

    Map<String, dynamic> postingResult(Map<String, dynamic> response) {
      final data =
          Map<String, dynamic>.from((response['data'] as Map?) ?? response);
      final result =
          Map<String, dynamic>.from((data['hasilPosting'] as Map?) ?? data);
      return {
        'diposting': result['diposting'],
        'gagal': result['gagal'],
        'dilewati': result['dilewati'],
        'pesan': result['pesan'],
      };
    }

    final audit = <String, dynamic>{};
    for (final kind in kinds) {
      final before = await load(kind);
      final readyIds = rows(before)
          .where((e) => e['siap'] == true && e['id'] != null)
          .map((e) => e['id'])
          .take(_target)
          .toList();
      expect(readyIds.length, _target,
          reason: '$kind harus menyediakan 100 dokumen siap posting');

      final posted = kind == 'hpp' || kind == 'penjualan'
          ? await call('laporan_keuangan_pendukung', {
              'jenis': kind,
              'mulai': '2026-09-01',
              'sampai': '2026-09-30',
              'posting': true,
              'posting_ids': readyIds,
              'batasRiwayat': 10000,
            })
          : await call('posting_${kind}_terapkan', {
              'toko_id': 1,
              'mulai': '2026-09-01',
              'sampai': '2026-09-30',
              'posting_ids': readyIds,
              'batasRiwayat': 10000,
            });

      final after = await load(kind);
      final pendingRows = rows(after);
      final historyRows = rows(after, key: 'rincianSudahDiposting');
      // ignore: avoid_print
      print('POSTING_RAW_${kind.toUpperCase()}=${jsonEncode({
            'respons': postingResult(posted),
            'pendingBefore': rows(before).length,
            'pendingAfter': pendingRows.length,
            'historyBefore': rows(before, key: 'rincianSudahDiposting').length,
            'historyAfter': historyRows.length,
          })}');
      expect(pendingRows.length, greaterThanOrEqualTo(_target),
          reason: '$kind harus menyisakan minimal 100 belum diposting');
      expect(historyRows.length, greaterThanOrEqualTo(_target),
          reason: '$kind harus menampilkan minimal 100 telah diposting');
      expect(
        pendingRows.every((e) =>
            e['sudahDiposting'] == false &&
            '${e['statusPosting']}'.startsWith('BELUM_DIPOSTING_')),
        isTrue,
        reason: '$kind harus memberi status eksplisit pada semua draf',
      );
      expect(
        historyRows.every((e) =>
            e['sudahDiposting'] == true &&
            e['statusPosting'] == 'SUDAH_DIPOSTING'),
        isTrue,
        reason: '$kind harus memberi status eksplisit pada semua riwayat',
      );
      audit[kind] = {
        'permintaanPosting': readyIds.length,
        'responsPosting': postingResult(posted),
        'belumDiposting': pendingRows.length,
        'telahDiposting': historyRows.length,
        'status': 'PASS',
      };
      // ignore: avoid_print
      print('POSTING_EXECUTE_${kind.toUpperCase()}=${jsonEncode(audit[kind])}');
    }

    final summary = {
      'toko': 'Demo',
      'tokoSumber': 'Demo',
      'periode': '2026-09-01 s.d. 2026-09-30',
      'posting': audit,
      'status': 'PASS',
    };
    final output = Directory(_outputDir)..createSync(recursive: true);
    File('${output.path}\\posting-execution-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
      flush: true,
    );
  }, timeout: const Timeout(Duration(hours: 1)));
}
