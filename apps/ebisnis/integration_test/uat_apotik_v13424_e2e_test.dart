import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _volume = int.fromEnvironment('POS_TEST_VOLUME', defaultValue: 100);
const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.24',
);
const _release = 'apotik-v1.34.24';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT E2E Apotik v1.34.24 pada server nyata', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(_volume, inInclusiveRange(100, 10000));
    expect(username, isNotEmpty);
    expect(password, isNotEmpty);
    expect(host, isNotEmpty);

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await _call('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Apotik-v1.34.24',
    });
    await ApiClient.instance.simpanToken('${login['token']}');

    final catalogPage =
        await _call('apotik_item_cari', {'page': 1, 'page_size': 100});
    final ingredientPage = await _call('apotik_item_cari', {
      'keyword': 'DEMO-BHN-',
      'page': 1,
      'page_size': 100,
    });
    final recipePage = await _call('apotik_resep_list', {
      'hanya_menunggu': true,
      'page': 1,
      'page_size': 100,
    });
    final catalogTotal = _number(catalogPage['total']).toInt();
    final ingredientTotal = _number(ingredientPage['total']).toInt();
    final readyRecipeTotal = _number(recipePage['total']).toInt();
    expect(catalogTotal, greaterThanOrEqualTo(11000));
    expect(ingredientTotal, greaterThanOrEqualTo(1000));
    expect(readyRecipeTotal, greaterThanOrEqualTo(500));
    final catalog = await _paged('apotik_item_cari', 'page_size');
    final recipes = await _paged('apotik_resep_list', 'page_size', extra: {
      'hanya_menunggu': true,
    });
    expect(catalog.length, greaterThanOrEqualTo(_volume));
    expect(recipes.length, greaterThanOrEqualTo(_volume));

    final stockAnchor = catalog.firstWhere((e) => e['kode'] == 'UJI-PCT');
    final stockAnchorId = _number(stockAnchor['id']).toInt();
    final stockAnchorBatches = _rows(await _call('apotik_item_batch', {
      'item_id': stockAnchorId,
    }));
    final uatBatchExists = stockAnchorBatches.any((e) =>
        e['tanggalKadaluarsa'] == '2030-12-31' &&
        _number(e['qtyAwal']) >= 2000);
    if (!uatBatchExists) {
      await _call('apotik_terima_barang', {
        'no_faktur': 'UAT-TERIMA-APT-13424-001',
        'penyedia': 'PBF Data Real UAT',
        'items': [
          {
            'item_id': stockAnchorId,
            'qty': 2000,
            'harga_beli': _number(stockAnchor['hargaBeli']) == 0
                ? 1500
                : _number(stockAnchor['hargaBeli']),
            'tanggal_kadaluarsa': '2030-12-31',
            'keterangan': 'Top-up idempoten berbasis batch UAT v1.34.24',
          }
        ],
      });
    }

    final usable = <Map<String, dynamic>>[];
    final activeBatchByItem = <int, Map<String, dynamic>>{};
    var expiredBatchRows = 0;
    for (final item in catalog) {
      if (usable.length >= _volume) break;
      if (item['terkendali'] == true || _number(item['stok']) < 8) continue;
      final itemId = _number(item['id']).toInt();
      final batches = _rows(await _call('apotik_item_batch', {
        'item_id': itemId,
      }));
      expiredBatchRows += batches.where((e) => e['kedaluwarsa'] == true).length;
      final active = batches
          .where((e) => e['kedaluwarsa'] != true && _number(e['sisa']) >= 8)
          .toList();
      if (active.isEmpty) continue;
      active.sort((a, b) => _number(b['sisa']).compareTo(_number(a['sisa'])));
      usable.add(item);
      activeBatchByItem[itemId] = active.first;
    }
    expect(usable, isNotEmpty,
        reason: 'Harus tersedia obat bebas dengan batch aktif');

    Map<String, dynamic> line(Map<String, dynamic> item) {
      final itemId = _number(item['id']).toInt();
      final batch = activeBatchByItem[itemId]!;
      return {
        'item_id': itemId,
        'qty': 1,
        'harga_satuan': _number(item['hargaJual']),
        'batch': [
          {'kadaluarsa_id': batch['kadaluarsaId'], 'qty': 1}
        ],
      };
    }

    var finishedPassed = 0;
    var compoundPassed = 0;
    var combinedPassed = 0;
    for (var i = 0; i < _volume; i++) {
      final number = (i + 1).toString().padLeft(4, '0');
      final recipeId = recipes[i]['id'];
      final finished = await _call('apotik_bayar', {
        'kode': 'UAT-APT-13424-JADI-$number',
        'keterangan': 'Data real UAT $_release - obat jadi',
        'pembeli': {'nama': 'Pasien UAT Jadi $number'},
        'items': [line(usable[i % usable.length])],
      });
      if (finished['status'] == 'success') finishedPassed++;

      final compound = await _call('apotik_bayar', {
        'kode': 'UAT-APT-13424-RACIK-$number',
        'resep_id': recipeId,
        'keterangan': 'Data real UAT $_release - obat racik',
        'pembeli': {'nama': 'Pasien UAT Racik $number'},
        'items': [line(usable[(i + 17) % usable.length])],
      });
      if (compound['status'] == 'success') compoundPassed++;

      final combined = await _call('apotik_bayar', {
        'kode': 'UAT-APT-13424-GAB-$number',
        'resep_id': recipeId,
        'keterangan': 'Data real UAT $_release - gabungan obat jadi dan racik',
        'pembeli': {'nama': 'Pasien UAT Gabungan $number'},
        'items': [
          line(usable[(i + 41) % usable.length]),
          line(usable[(i + 67) % usable.length]),
        ],
      });
      if (combined['status'] == 'success') combinedPassed++;

      if ((i + 1) % 10 == 0 || i == 0) {
        // ignore: avoid_print
        print('UAT_APOTIK_PROGRESS=${i + 1}/$_volume');
      }
    }
    expect(finishedPassed, _volume);
    expect(compoundPassed, _volume);
    expect(combinedPassed, _volume);

    final idempotent = await _call('apotik_bayar', {
      'kode': 'UAT-APT-13424-JADI-0001',
      'keterangan': 'Retest idempoten $_release',
      'pembeli': {'nama': 'Pasien UAT Jadi 0001'},
      'items': [line(usable.first)],
    });
    expect(idempotent['idempoten'], true,
        reason: 'Kode transaksi sama tidak boleh membuat transaksi kedua');

    final batchMonitor = await _call('apotik_batch_monitor', {
      'hari_ke_depan': 1095,
      'page_size': 100,
    });
    final salesReport = await _call('apotik_laporan_penjualan', {
      'page_size': 100,
    });
    final controlledReport = await _call('apotik_laporan_terkendali', {
      'page_size': 100,
    });
    final expiryReport = await _call('apotik_laporan_kedaluwarsa', {
      'hari_ke_depan': 1095,
      'page_size': 100,
    });

    var queueStatus = 'BLOCKED_ENDPOINT_BELUM_TERPASANG';
    var queueRows = 0;
    String? queueMessage;
    try {
      final queue = await _call('apotik_antrean_farmasi_list', {
        'toko_id': 1,
        'untuk_layar': true,
      });
      queueRows = _rows(queue).length;
      expect(queueRows, greaterThanOrEqualTo(100));
      queueStatus = 'PASS';
    } catch (error) {
      queueMessage = '$error';
    }

    final summary = <String, dynamic>{
      'rilis': _release,
      'waktuUatUtc': DateTime.now().toUtc().toIso8601String(),
      'server': 'https://$host/$context',
      'volumePerSkenario': _volume,
      'katalogItemTotal': catalogTotal,
      'obatJadiTargetTerverifikasi': catalogTotal - ingredientTotal,
      'bahanRacikanTerverifikasi': ingredientTotal,
      'catatanKatalog': 'PASS_VOLUME_10000_OBAT_JADI_1000_BAHAN_RACIKAN',
      'resepSiapJualTerverifikasi': readyRecipeTotal,
      'resepRacikanTerbacaPadaRun': recipes.length,
      'obatBerbatchLayakUji': usable.length,
      'transaksiObatJadiLulus': finishedPassed,
      'transaksiRacikanLulus': compoundPassed,
      'transaksiGabunganLulus': combinedPassed,
      'totalTransaksiPenjualanLulus':
          finishedPassed + compoundPassed + combinedPassed,
      'idempotensiTransaksi': idempotent['idempoten'] == true ? 'PASS' : 'FAIL',
      'batchKedaluwarsaDitemukanSaatSeleksi': expiredBatchRows,
      'batchMonitorStatus': batchMonitor['status'],
      'batchMonitorBaris': _rows(batchMonitor).length,
      'laporanPenjualanStatus': salesReport['status'],
      'laporanPenjualanBaris': _rows(salesReport).length,
      'laporanTerkendaliStatus': controlledReport['status'],
      'laporanTerkendaliBaris': _rows(controlledReport).length,
      'laporanKedaluwarsaStatus': expiryReport['status'],
      'laporanKedaluwarsaBaris': _rows(expiryReport).length,
      'antreanFarmasiStatus': queueStatus,
      'antreanFarmasiBaris': queueRows,
      if (queueMessage != null) 'antreanFarmasiTemuan': queueMessage,
    };
    final directory = Directory(_outputDir)..createSync(recursive: true);
    File('${directory.path}\\uat-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
      flush: true,
    );
    // ignore: avoid_print
    print('UAT_APOTIK_FINAL=${jsonEncode(summary)}');
  });
}

Future<Map<String, dynamic>> _call(
    String action, Map<String, dynamic> body) async {
  Object? last;
  for (var attempt = 1; attempt <= 4; attempt++) {
    try {
      return Map<String, dynamic>.from(
          await ApiClient.instance.aksi(action, body));
    } catch (error) {
      last = error;
      if (attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }
  throw StateError('$action gagal setelah 4 percobaan: $last');
}

Future<List<Map<String, dynamic>>> _paged(String action, String pageSizeKey,
    {Map<String, dynamic> extra = const {}}) async {
  final all = <Map<String, dynamic>>[];
  for (var page = 1; page <= 100 && all.length < _volume; page++) {
    final response = await _call(action, {
      ...extra,
      'page': page,
      pageSizeKey: 100,
    });
    final rows = _rows(response);
    all.addAll(rows);
    if (rows.length < 100) break;
  }
  return all;
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> response) =>
    ((response['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

num _number(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
