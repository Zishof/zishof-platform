import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _volume = int.fromEnvironment('POS_TEST_VOLUME', defaultValue: 100);
const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.25-cashier',
);
const _release = 'apotik-v1.34.25+187';
const _runId = String.fromEnvironment('POS_TEST_RUN_ID', defaultValue: 'R2');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'UAT kasir Apotik v1.34.25: 100 data per mode pada server nyata',
    (tester) async {
      const token = String.fromEnvironment('POS_TEST_TOKEN');
      const host = String.fromEnvironment('POS_TEST_HOST');
      const context = String.fromEnvironment('POS_TEST_CONTEXT');
      expect(_volume, greaterThanOrEqualTo(100));
      expect(token, isNotEmpty, reason: 'POS_TEST_TOKEN wajib diisi');
      expect(host, isNotEmpty, reason: 'POS_TEST_HOST wajib diisi');

      await ServerConfig.instance
          .simpan(host: host, contextPath: context, https: true);
      await ApiClient.instance.simpanToken(token);

      final statusProvision = await _call('apotik_provision_demo', {
        'konfirmasi': 'SEED-DEMO-APOTIK',
        'status_only': true,
      });
      _expectSuccess('status apotik_provision_demo', statusProvision);
      if (statusProvision['selesai'] != true ||
          statusProvision['berhasil'] != true ||
          _map(statusProvision['verifikasi'])['lulus'] != true) {
        final provision = await _call('apotik_provision_demo', {
          'konfirmasi': 'SEED-DEMO-APOTIK',
          'background': true,
        });
        _expectSuccess('apotik_provision_demo', provision);
      }
      final volumeServer = await _tungguProvisioning();
      // ignore: avoid_print
      print('UAT_KASIR_APOTIK_TAHAP=provisioning_selesai');

      final hakResponse = await _call('apotik_item_cari', {
        'page': 1,
        'page_size': 100,
      });
      _expectSuccess('apotik_item_cari', hakResponse);
      final hak = _map(hakResponse['hak']);
      for (final menu in const [
        'apotik_kasir',
        'apotik_resep',
        'apotik_racikan',
      ]) {
        final crud = _map(hak[menu]);
        expect(crud['create'], true,
            reason: '$menu harus terbuka untuk transaksi UAT');
      }

      final obat = await _obatBerbatch(_volume * 2);
      // ignore: avoid_print
      print('UAT_KASIR_APOTIK_TAHAP=obat_dan_batch_siap:${obat.length}');
      final racikan = await _paged(
        'apotik_racikan_list',
        extra: const {'page_size': 100},
        minimumRows: _volume,
      );
      expect(racikan.length, greaterThanOrEqualTo(_volume),
          reason: 'Menu Racikan wajib menyediakan minimal $_volume formula');
      // ignore: avoid_print
      print('UAT_KASIR_APOTIK_TAHAP=racikan_siap:${racikan.length}');
      final produksi = _rows(await _call('apotik_produksi_katalog', {
        'page_size': 100,
      }));
      expect(produksi.length, greaterThanOrEqualTo(_volume),
          reason:
              'Menu Produksi Farmasi wajib menyediakan minimal $_volume formula');
      // ignore: avoid_print
      print('UAT_KASIR_APOTIK_TAHAP=produksi_siap:${produksi.length}');
      final resepCampuran = await _resepCampuran(_volume);
      expect(resepCampuran.length, greaterThanOrEqualTo(_volume),
          reason:
              'Menu Tebus Resep wajib menyediakan minimal $_volume resep campuran');
      // ignore: avoid_print
      print(
          'UAT_KASIR_APOTIK_TAHAP=resep_campuran_siap:${resepCampuran.length}');

      var otcLulus = 0;
      var resepDokterLulus = 0;
      var racikanLulus = 0;
      var produksiLulus = 0;
      var tebusResepLulus = 0;
      var tebusBarisObatJadi = 0;
      var tebusBarisRacikan = 0;

      Map<String, dynamic>? otcPertama;
      Map<String, dynamic>? racikanPertama;
      Map<String, dynamic>? produksiPertama;
      Map<String, dynamic>? tebusPertama;

      for (var i = 0; i < _volume; i++) {
        final nomor = (i + 1).toString().padLeft(4, '0');

        final otc = await _call('apotik_bayar', {
          'kode': 'UAT-APT-13425-$_runId-OTC-$nomor',
          'keterangan': 'UAT $_release - OTC/Obat Bebas',
          'pembeli': {'nama': 'Pembeli UAT OTC $nomor'},
          'items': [_barisObat(obat[i])],
        });
        _expectSuccess('OTC $nomor', otc);
        otcPertama ??= otc;
        otcLulus++;

        final resepDokter = await _call('apotik_bayar', {
          'kode': 'UAT-APT-13425-$_runId-DOKTER-$nomor',
          'keterangan': 'UAT $_release - Resep Dokter',
          'nama_dokter': 'dr. UAT $nomor',
          'pembeli': {
            'nama': 'Pasien UAT Dokter $nomor',
            'alamat': 'Alamat data sample $nomor',
          },
          'items': [_barisObat(obat[_volume + i])],
        });
        _expectSuccess('Resep Dokter $nomor', resepDokter);
        resepDokterLulus++;

        final rowRacikan = racikan[i];
        final jualRacikan = await _call('apotik_bayar_racikan', {
          'kode': 'UAT-APT-13425-$_runId-RACIKAN-$nomor',
          'keterangan': 'UAT $_release - Racikan',
          'pembeli': {'nama': 'Pasien UAT Racikan $nomor'},
          'items': [
            {
              'racikan_id': rowRacikan['racikanId'] ?? rowRacikan['id'],
              'qty': 1,
              'harga_satuan': _number(rowRacikan['hargaJual']),
            }
          ],
        });
        _expectSuccess('Racikan $nomor', jualRacikan);
        racikanPertama ??= jualRacikan;
        racikanLulus++;

        final rowProduksi = produksi[i];
        final prosesProduksi = await _call('apotik_produksi_proses', {
          'kode': 'UAT-APT-13425-$_runId-PRODUKSI-$nomor',
          'nomor_batch': 'BATCH-UAT-13425-$_runId-$nomor',
          'tanggal_kadaluarsa': '2030-12-31',
          'items': [
            {
              'item_id': rowProduksi['itemId'] ?? rowProduksi['id'],
              'qty': 1,
            }
          ],
        });
        _expectSuccess('Produksi Farmasi $nomor', prosesProduksi);
        produksiPertama ??= prosesProduksi;
        produksiLulus++;

        final resep = resepCampuran[i];
        final detail = List<Map<String, dynamic>>.from(resep['detail'] as List);
        final items = <Map<String, dynamic>>[];
        for (final baris in detail) {
          if (baris['racikan'] == true) {
            tebusBarisRacikan++;
            items.add({
              'racikan_id': baris['racikanId'] ?? baris['id'],
              'qty': _positive(baris['jumlah']),
              'harga_satuan': _number(baris['hargaJual']),
            });
          } else {
            tebusBarisObatJadi++;
            items.add({
              'item_id': baris['itemId'] ?? baris['id'],
              'qty': _positive(baris['jumlah']),
              'harga_satuan': _number(baris['hargaJual']),
            });
          }
        }
        expect(items.any((e) => e.containsKey('item_id')), true,
            reason: 'Tebus resep $nomor harus memuat obat jadi');
        expect(items.any((e) => e.containsKey('racikan_id')), true,
            reason: 'Tebus resep $nomor harus memuat racikan');
        final tebus = await _call('apotik_bayar_racikan', {
          'kode': 'UAT-APT-13425-$_runId-TEBUS-$nomor',
          'resep_id': resep['id'],
          'keterangan': 'UAT $_release - Tebus Resep campuran',
          'nama_dokter': 'dr. UAT Tebus $nomor',
          'pembeli': {
            'nama': 'Pasien UAT Tebus $nomor',
            'alamat': 'Alamat data sample tebus $nomor',
          },
          'items': items,
        });
        _expectSuccess('Tebus Resep $nomor', tebus);
        tebusPertama ??= tebus;
        tebusResepLulus++;

        if ((i + 1) % 10 == 0 || i == 0) {
          // ignore: avoid_print
          print('UAT_KASIR_APOTIK_PROGRESS=${i + 1}/$_volume');
        }
      }

      expect(otcLulus, _volume);
      expect(resepDokterLulus, _volume);
      expect(racikanLulus, _volume);
      expect(produksiLulus, _volume);
      expect(tebusResepLulus, _volume);

      final idempotensi = <String, bool>{};
      final otcUlang = await _call('apotik_bayar', {
        'kode': 'UAT-APT-13425-$_runId-OTC-0001',
        'items': [_barisObat(obat.first)],
      });
      idempotensi['otc'] =
          otcUlang['idempoten'] == true && otcUlang['id'] == otcPertama?['id'];

      final racikanUlang = await _call('apotik_bayar_racikan', {
        'kode': 'UAT-APT-13425-$_runId-RACIKAN-0001',
        'items': [
          {
            'racikan_id': racikan.first['racikanId'] ?? racikan.first['id'],
            'qty': 1,
          }
        ],
      });
      idempotensi['racikan'] = racikanUlang['idempoten'] == true &&
          racikanUlang['id'] == racikanPertama?['id'];

      final produksiUlang = await _call('apotik_produksi_proses', {
        'kode': 'UAT-APT-13425-$_runId-PRODUKSI-0001',
        'nomor_batch': 'BATCH-UAT-13425-$_runId-0001',
        'tanggal_kadaluarsa': '2030-12-31',
        'items': [
          {
            'item_id': produksi.first['itemId'] ?? produksi.first['id'],
            'qty': 1,
          }
        ],
      });
      final produksiUlangKedua = await _call('apotik_produksi_proses', {
        'kode': 'UAT-APT-13425-$_runId-PRODUKSI-0001',
        'nomor_batch': 'BATCH-UAT-13425-$_runId-0001',
        'tanggal_kadaluarsa': '2030-12-31',
        'items': [
          {
            'item_id': produksi.first['itemId'] ?? produksi.first['id'],
            'qty': 1,
          }
        ],
      });
      // Respons proses pertama berisi daftar batch hasil dan tidak memiliki
      // satu id induk. Dua retry harus sama-sama dikenali dan menunjuk id yang
      // sama; itulah bukti tidak ada produksi ganda.
      idempotensi['produksi'] = produksiUlang['idempoten'] == true &&
          produksiUlangKedua['idempoten'] == true &&
          produksiUlang['id'] == produksiUlangKedua['id'];

      final tebusUlang = await _call('apotik_bayar_racikan', {
        'kode': 'UAT-APT-13425-$_runId-TEBUS-0001',
        'resep_id': resepCampuran.first['id'],
        'items': const [
          {'item_id': -1, 'qty': 1},
        ],
      });
      idempotensi['tebusResep'] = tebusUlang['idempoten'] == true &&
          tebusUlang['id'] == tebusPertama?['id'];
      expect(idempotensi.values.every((value) => value), true,
          reason: 'Retry tidak boleh membuat transaksi/produksi ganda');

      final resepPertamaMasihMenunggu = await _call('apotik_resep_list', {
        'keyword': '${resepCampuran.first['kode']}',
        'hanya_menunggu': true,
        'page_size': 10,
      });
      expect(
        _rows(resepPertamaMasihMenunggu)
            .any((e) => '${e['id']}' == '${resepCampuran.first['id']}'),
        false,
        reason: 'Resep yang selesai tidak boleh tetap muncul di antrean tebus',
      );

      final laporan = await _call('apotik_laporan_penjualan', {
        'page_size': 100,
      });
      _expectSuccess('Laporan Penjualan', laporan);
      expect(_rows(laporan).length, greaterThanOrEqualTo(100));

      final summary = <String, dynamic>{
        'rilis': _release,
        'runId': _runId,
        'waktuUatUtc': DateTime.now().toUtc().toIso8601String(),
        'server': 'https://$host/$context',
        'volumePerMenu': _volume,
        'provisioning': volumeServer,
        'fiturTerbuka': {
          'apotik_kasir': _map(hak['apotik_kasir'])['create'] == true,
          'apotik_resep': _map(hak['apotik_resep'])['create'] == true,
          'apotik_racikan': _map(hak['apotik_racikan'])['create'] == true,
        },
        'katalogTerbaca': {
          'otc': obat.length,
          'resepDokter': _volume,
          'racikan': racikan.length,
          'produksiFarmasi': produksi.length,
          'tebusResepCampuran': resepCampuran.length,
        },
        'transaksiLulus': {
          'otcObatBebas': otcLulus,
          'resepDokter': resepDokterLulus,
          'racikan': racikanLulus,
          'produksiFarmasi': produksiLulus,
          'tebusResep': tebusResepLulus,
        },
        'tebusResepBaris': {
          'obatJadi': tebusBarisObatJadi,
          'racikan': tebusBarisRacikan,
        },
        'idempotensi': idempotensi,
        'resepPertamaDitandaiDitebus': true,
        'laporanPenjualanBaris': _rows(laporan).length,
        'status': 'PASS',
      };
      final directory = Directory(_outputDir)..createSync(recursive: true);
      File('${directory.path}\\uat-kasir-summary.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(summary),
        flush: true,
      );
      // ignore: avoid_print
      print('UAT_KASIR_APOTIK_FINAL=${jsonEncode(summary)}');
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Future<Map<String, dynamic>> _tungguProvisioning() async {
  Map<String, dynamic> status = const {};
  for (var attempt = 0; attempt < 120; attempt++) {
    status = await _call('apotik_provision_demo', {
      'konfirmasi': 'SEED-DEMO-APOTIK',
      'status_only': true,
    });
    _expectSuccess('status provisioning', status);
    final verifikasi = _map(status['verifikasi']);
    if (status['selesai'] == true &&
        status['berhasil'] == true &&
        verifikasi['lulus'] == true) {
      return verifikasi;
    }
    if (status['berjalan'] != true &&
        status['selesai'] == true &&
        status['berhasil'] != true) {
      fail('Provisioning gagal pada tahap ${status['tahap']}: '
          '${status['ringkasan']}');
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
  fail('Provisioning belum selesai dalam 10 menit: ${status['tahap']}');
}

Future<List<Map<String, dynamic>>> _obatBerbatch(int target) async {
  final katalog = await _paged(
    'apotik_item_cari',
    extra: const {'keyword': 'DEMO-OBT-', 'page_size': 100},
    minimumRows: target + 100,
  );
  final hasil = <Map<String, dynamic>>[];
  for (final item in katalog) {
    if (hasil.length >= target) break;
    if (item['terkendali'] == true || _number(item['stok']) < 4) continue;
    final batchResponse = await _call('apotik_item_batch', {
      'item_id': item['itemId'] ?? item['id'],
    });
    _expectSuccess('batch ${item['kode']}', batchResponse);
    final batch = _rows(batchResponse)
        .where((e) => e['kedaluwarsa'] != true && _number(e['sisa']) >= 4)
        .toList()
      ..sort((a, b) => _number(a['tanggal']).compareTo(_number(b['tanggal'])));
    if (batch.isEmpty) continue;
    hasil.add({...item, '_batch': batch.first});
  }
  expect(hasil.length, greaterThanOrEqualTo(target),
      reason: 'Harus tersedia $target obat bebas berbeda dengan batch aktif');
  return hasil;
}

Future<List<Map<String, dynamic>>> _resepCampuran(int target) async {
  final hasil = <Map<String, dynamic>>[];
  // Provisioning selalu menautkan formula ke resep SAMPLE yang masih belum
  // ditebus. Ambil antrean server apa adanya agar run UAT berulang tidak
  // terpaku pada 250 kode lama yang sebagian sudah selesai pada run terdahulu.
  final kandidat = await _paged(
    'apotik_resep_list',
    extra: const {
      'keyword': 'RSP-DEMO-',
      'hanya_menunggu': true,
      'page_size': 100,
    },
    // Endpoint mengurutkan resep terbaru terlebih dahulu, sedangkan
    // provisioning menautkan formula ke resep sample aktif paling awal.
    // Ambil seluruh antrean sample (maksimum 5.000) lalu periksa dari belakang.
    minimumRows: 5000,
  );
  for (final resep in kandidat.reversed) {
    if (hasil.length >= target) break;
    final kode = '${resep['kode'] ?? ''}';
    if (!kode.startsWith('RSP-DEMO-')) continue;
    final detailResponse = await _call('apotik_resep_detail', {
      'resep_id': resep['id'],
    });
    _expectSuccess('detail $kode', detailResponse);
    final detail = _rows(detailResponse);
    if (detail.any((e) => e['racikan'] == true) &&
        detail.any((e) => e['racikan'] != true)) {
      hasil.add({...resep, 'detail': detail});
    }
  }
  return hasil;
}

Map<String, dynamic> _barisObat(Map<String, dynamic> item) {
  final batch = _map(item['_batch']);
  return {
    'item_id': item['itemId'] ?? item['id'],
    'qty': 1,
    'harga_satuan': _number(item['hargaJual']),
    'batch': [
      {'kadaluarsa_id': batch['kadaluarsaId'], 'qty': 1},
    ],
  };
}

Future<List<Map<String, dynamic>>> _paged(
  String action, {
  Map<String, dynamic> extra = const {},
  required int minimumRows,
}) async {
  final all = <Map<String, dynamic>>[];
  for (var page = 1; page <= 100 && all.length < minimumRows; page++) {
    final response = await _call(action, {
      ...extra,
      'page': page,
      'page_size': 100,
    });
    _expectSuccess('$action halaman $page', response);
    final rows = _rows(response);
    all.addAll(rows);
    if (rows.length < 100) break;
  }
  return all;
}

Future<Map<String, dynamic>> _call(
  String action,
  Map<String, dynamic> body,
) async {
  Object? last;
  for (var attempt = 1; attempt <= 4; attempt++) {
    try {
      return Map<String, dynamic>.from(
        await ApiClient.instance.aksi(action, body),
      );
    } catch (error) {
      last = error;
      if (attempt < 4) {
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
  }
  throw StateError('$action gagal setelah 4 percobaan: $last');
}

void _expectSuccess(String label, Map<String, dynamic> response) {
  expect(
    response['status'],
    anyOf('success', '00'),
    reason: '$label ditolak: '
        '${response['description'] ?? response['message'] ?? response}',
  );
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> response) =>
    ((response['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

num _number(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

double _positive(Object? value) {
  final number = _number(value).toDouble();
  return number > 0 ? number : 1;
}
