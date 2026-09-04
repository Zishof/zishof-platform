import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _marker = 'UAT Apotik v1.34.24 - sumber laporan keuangan';
const _volume = 100;
const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.24',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('100 jurnal sample mengisi seluruh laporan keuangan Apotik',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const tokenTersimpan = String.fromEnvironment('POS_TEST_TOKEN');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');

    expect(host, isNotEmpty);
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    if (tokenTersimpan.isNotEmpty) {
      await ApiClient.instance.simpanToken(tokenTersimpan);
    } else {
      expect(username, isNotEmpty);
      expect(password, isNotEmpty);
      final login = await ApiClient.instance.aksi('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-Apotik-Laporan-Keuangan',
      });
      await ApiClient.instance.simpanToken('${login['token']}');
    }

    Future<Map<String, dynamic>> call(
            String action, Map<String, dynamic> body) async =>
        Map<String, dynamic>.from(await ApiClient.instance.aksi(action, body));

    List<Map<String, dynamic>> rows(Map<String, dynamic> response,
            {String key = 'data'}) =>
        ((response[key] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    Future<Map<String, dynamic>> account(String code) async {
      final found = rows(await call('akun_list', {
        'keyword': code,
        'limit': 100,
      }))
          .where((e) => '${e['kode']}' == code && e['leaf'] == true)
          .toList();
      expect(found, hasLength(1), reason: 'Akun $code harus unik dan leaf');
      return found.single;
    }

    final cash = await account('111.101');
    final inventory = await account('151.200');
    final revenue = await account('410.900');
    final cost = await account('510.900');

    final existing = rows(await call('jurnal_umum_list', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
      'cari': _marker,
      'status': '',
      'page': 1,
      'page_size': 500,
    }));
    final byDescription = {
      for (final row in existing) '${row['keterangan']}': row,
    };

    final toPost = <int>[];
    var created = 0;
    for (var i = 1; i <= _volume; i++) {
      final number = i.toString().padLeft(3, '0');
      final description = '$_marker $number';
      var journal = byDescription[description];
      if (journal == null) {
        final sale = 125000.0 + (i * 1750);
        final hpp = sale * 0.62;
        final made = await call('jurnal_umum_simpan', {
          'tanggal': '2026-09-${((i - 1) % 30 + 1).toString().padLeft(2, '0')}',
          'keterangan': description,
          'jenisTransaksiId': 0,
          'baris': [
            {
              'akunId': cash['id'],
              'debet': sale,
              'kredit': 0,
              'keterangan': 'Kas penjualan obat sample $number',
            },
            {
              'akunId': revenue['id'],
              'debet': 0,
              'kredit': sale,
              'keterangan': 'Pendapatan penjualan obat sample $number',
            },
            {
              'akunId': cost['id'],
              'debet': hpp,
              'kredit': 0,
              'keterangan': 'HPP obat sample $number',
            },
            {
              'akunId': inventory['id'],
              'debet': 0,
              'kredit': hpp,
              'keterangan': 'Pengurangan persediaan sample $number',
            },
          ],
        });
        journal = {'id': made['id'], 'terposting': false};
        created++;
      }
      if (journal['terposting'] != true && journal['id'] is num) {
        toPost.add((journal['id'] as num).toInt());
      }
      if (i % 10 == 0) {
        // ignore: avoid_print
        print('UAT_LAPORAN_KEUANGAN_PROGRESS=$i/$_volume');
      }
    }
    if (toPost.isNotEmpty) {
      await call('jurnal_umum_posting', {'ids': toPost});
    }

    final verified = rows(await call('jurnal_umum_list', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
      'cari': _marker,
      'status': 'posting',
      'page': 1,
      'page_size': 500,
    }));
    expect(verified.length, greaterThanOrEqualTo(_volume));
    expect(
        verified.take(_volume).every((e) => e['terposting'] == true), isTrue);

    // Gunakan mekanisme pemetaan resmi yang menurunkan Kelompok Laporan dari
    // bagan akun/akun induk. Ini memperbaiki master sumber secara permanen dan
    // dapat diaudit; bukan menambahkan jurnal penyeimbang sementara hanya agar
    // laporan tampak berisi.
    final mappingProposal = await call('pemetaan_akun_usulan', {
      'batasContoh': 100,
    });
    final unmappedBefore =
        (mappingProposal['jumlahBelumDipetakan'] as num?)?.toInt() ?? 0;
    Map<String, dynamic> mappingResult = const {};
    if (unmappedBefore > 0) {
      mappingResult = await call('pemetaan_akun_terapkan', {});
    }
    // Ringkas bukti runtime agar log UAT tetap dapat diaudit tanpa menyalin
    // ratusan detail pemetaan yang sudah tersedia melalui API sumber.
    // ignore: avoid_print
    print('UAT_PEMETAAN_LAPORAN=${jsonEncode({
          'belumDipetakanSebelum': unmappedBefore,
          'dipetakan': mappingResult['dipetakan'] ?? 0,
          'kelompokBaru': mappingResult['kelompokBaru'] ?? 0,
          'jenisLaporanBaru': mappingResult['jenisLaporanBaru'] ?? 0,
          'gagal': mappingResult['gagal'] ?? 0,
        })}');

    const reports = <String, String>{
      'akn_laba_rugi': 'Laba Rugi',
      'akn_neraca': 'Neraca',
      'akn_arus_kas': 'Arus Kas',
      'akn_jurnal': 'Jurnal Umum',
      'akn_buku_besar': 'Buku Besar',
      'akn_neraca_saldo': 'Trial Balance',
    };
    final reportRows = <String, int>{};
    for (final entry in reports.entries) {
      final response = await call('laporan_jalankan', {
        'r': entry.key,
        'tglMulai': '2026-09-01',
        'tglSampai': '2026-09-30',
      });
      final reportData = (response['baris'] as List?) ?? const [];
      final count = reportData.length;
      expect(count, greaterThan(0),
          reason: '${entry.value} tidak boleh kosong setelah jurnal diposting');
      expect(jsonEncode(reportData), isNot(contains('Belum ada data')),
          reason:
              '${entry.value} tidak boleh lulus hanya karena satu baris pesan kosong');
      reportRows[entry.key] = count;
    }
    expect(reportRows['akn_laba_rugi'], greaterThanOrEqualTo(4));
    expect(reportRows['akn_jurnal'], greaterThanOrEqualTo(_volume * 4));
    expect(reportRows['akn_buku_besar'], greaterThanOrEqualTo(_volume * 4));

    final summary = <String, dynamic>{
      'sumberJurnalTarget': _volume,
      'sumberJurnalDibuatPadaRun': created,
      'sumberJurnalDipostingPadaRun': toPost.length,
      'sumberJurnalTerpostingTerverifikasi': verified.length,
      'periode': '2026-09-01 s.d. 2026-09-30',
      'akunKas': '111.101 KAS YAYASAN',
      'akunPersediaan': '151.200 PERSEDIAAN BARANG LAINNYA',
      'akunPendapatan': '410.900 PENDAPATAN PENJUALAN TOKO',
      'akunHpp': '510.900 BEBAN POKOK PENJUALAN TOKO',
      'akunBelumDipetakanSebelum': unmappedBefore,
      'akunDipetakanPadaRun': mappingResult['dipetakan'] ?? 0,
      'kelompokLaporanBaruPadaRun': mappingResult['kelompokBaru'] ?? 0,
      'jenisLaporanBaruPadaRun': mappingResult['jenisLaporanBaru'] ?? 0,
      'barisLaporan': reportRows,
      'status': 'PASS',
    };
    final output = Directory(_outputDir)..createSync(recursive: true);
    File('${output.path}\\financial-report-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
      flush: true,
    );
    // ignore: avoid_print
    print('UAT_LAPORAN_KEUANGAN=${jsonEncode(summary)}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
