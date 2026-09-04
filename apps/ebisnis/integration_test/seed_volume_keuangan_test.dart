import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _prefix = 'UAT-VOL-FIN-20260904';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed volume Uang Muka LPJ Kas Besar Kas Kecil Reimbursement',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const volume = int.fromEnvironment('FIN_UAT_VOLUME', defaultValue: 1);

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Volume-Keuangan',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>> call(String action,
        [Map<String, dynamic>? body]) async {
      Object? last;
      for (var attempt = 1; attempt <= 4; attempt++) {
        try {
          return Map<String, dynamic>.from(
              await ApiClient.instance.aksi(action, body ?? const {}));
        } catch (e) {
          last = e;
          if (attempt < 4) {
            await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }
      throw StateError('$action gagal: $last');
    }

    List<Map<String, dynamic>> rows(Map<String, dynamic> r) =>
        ((r['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    Future<Map<String, Map<String, dynamic>>> indexed(String action) async =>
        {for (final r in rows(await call(action))) '${r['nama']}': r};

    final accounts = rows(await call('akun_list', {'limit': 5000}));
    final expense = accounts.firstWhere(
      (e) => e['leaf'] == true && '${e['kode']}'.startsWith('5'),
      orElse: () => accounts.firstWhere((e) => e['leaf'] == true),
    );
    final cashAdvanceOptions = await call('uang_muka_opsi');
    final satkers = ((cashAdvanceOptions['satuanKerja'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final satker = satkers.firstWhere(
      (e) => '${e['nama']}'.toUpperCase().contains('YAYASAN'),
      orElse: () => satkers.first,
    );
    final cashAdvanceType =
        ((cashAdvanceOptions['jenisUangMuka'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .first;
    final bigCashOptions = await call('kas_besar_opsi');
    final bigCashType = ((bigCashOptions['jenisKasBesar'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .first;
    final pettyOptions = await call('kas_kecil_opsi');
    final pettyType = ((pettyOptions['jenisKasKecil'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .first;

    final advanceByName = await indexed('uang_muka_daftar');
    final advanceLpjByName = await indexed('pj_uang_muka_daftar');
    final bigCashByName = await indexed('kas_besar_daftar');
    final bigCashLpjByName = await indexed('pj_kas_besar_daftar');
    final pettyByName = await indexed('kas_kecil_daftar');
    final refillByName = await indexed('penggantian_kas_kecil_daftar');
    final reimbursementByName = await indexed('reimbursement_daftar');

    Future<Map<String, dynamic>> ensureDocument({
      required Map<String, Map<String, dynamic>> index,
      required String name,
      required String saveAction,
      required String approveAction,
      required Map<String, dynamic> body,
    }) async {
      var row = index[name];
      if (row == null) {
        final made = await call(saveAction, {'nama': name, ...body});
        row = {'id': made['id'], 'nama': name, 'statusDokumen': 'Pengajuan'};
        index[name] = row;
      }
      if ('${row['statusDokumen']}' != 'Disetujui') {
        await call(approveAction, {
          'id': row['id'],
          'tanggalPersetujuan': '2026-09-04',
        });
        row['statusDokumen'] = 'Disetujui';
      }
      return row;
    }

    Future<void> submit(String prefix, Map<String, dynamic> row) async {
      if (row['dpcAda'] != true) {
        await call('${prefix}_ajukan_transfer', {'id': row['id']});
        row['dpcAda'] = true;
      }
    }

    Future<void> realizeBatch(String suffix, String nameMarker) async {
      final candidates = rows(await call('proses_transfer_kandidat'))
          .where((e) => '${e['nama']}'.contains(nameMarker))
          .toList();
      if (candidates.isEmpty) return;
      final processName =
          '$_prefix-TRANSFER-$suffix-B${DateTime.now().millisecondsSinceEpoch}';
      final options = await call('proses_transfer_opsi');
      final methods = ((options['caraPembayaran'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final method = methods.firstWhere(
        (e) => '${e['nama']}'.toUpperCase().contains('BCA'),
        orElse: () => methods.first,
      );
      final made = await call('proses_transfer_simpan', {
        'nama': processName,
        'keterangan': 'Batch realisasi data sample volume UAT Keuangan.',
        'caraPembayaranId': method['id'],
        'tanggalPembuatan': '2026-09-04',
        'dptIds': candidates.map((e) => e['id']).toList(),
      });
      final process = {'id': made['id'], 'statusDokumen': 'Draft'};
      if ('${process['statusDokumen']}' == 'Draft') {
        await call('proses_transfer_setujui', {
          'id': process['id'],
          'tanggalPersetujuan': '2026-09-04',
          'catatanPersetujuan': 'Disetujui untuk data sample volume UAT.',
        });
      }
      final detail =
          await call('proses_transfer_detail', {'id': process['id']});
      for (final item in ((detail['item'] as List?) ?? const [])) {
        final row = item as Map;
        if (row['transfer'] != true && row['transitori'] != true) {
          await call('proses_transfer_tandai', {
            'dptId': row['id'],
            'mode': 'transfer',
          });
        }
      }
      final current = rows(await call('proses_transfer_daftar'))
          .firstWhere((e) => e['nama'] == processName);
      if ('${current['statusDokumen']}' != 'Terealisasi') {
        await call('proses_transfer_realisasikan', {
          'id': current['id'],
          'tanggalRealisasikan': '2026-09-04',
          'catatanRealisasi': 'Batch data sample UAT telah direalisasikan.',
        });
      }
    }

    var createdFlows = 0;
    final advances = <int, Map<String, dynamic>>{};
    for (var i = 1; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final day = (1 + ((i - 1) % 4)).toString().padLeft(2, '0');
      final name = '$_prefix-UM-$serial — Operasional Unit';
      final wasNew = !advanceByName.containsKey(name);
      final row = await ensureDocument(
        index: advanceByName,
        name: name,
        saveAction: 'uang_muka_simpan',
        approveAction: 'uang_muka_setujui',
        body: {
          'keterangan':
              'Uang muka pembelian ATK dan konsumsi kegiatan sample UAT.',
          'tanpaAnggaran': true,
          'ambilDariPr': false,
          'satuanKerjaId': satker['id'],
          'akunId': expense['id'],
          'workspaceId': 0,
          'jenisUangMukaId': cashAdvanceType['id'],
          'nilai': 150000 + (i % 5) * 10000,
          'mulai': '2026-09-$day',
          'sampai': '2026-09-$day',
          'selesai': '2026-09-$day',
          'statusDokumen': 'Pengajuan',
        },
      );
      await submit('uang_muka', row);
      advances[i] = row;
      if (wasNew) createdFlows++;
    }
    await realizeBatch('UANG-MUKA', '$_prefix-UM-');
    for (var i = 1; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final day = (1 + ((i - 1) % 4)).toString().padLeft(2, '0');
      await ensureDocument(
        index: advanceLpjByName,
        name: '$_prefix-LPJ-UM-$serial — Bukti Operasional',
        saveAction: 'pj_uang_muka_simpan',
        approveAction: 'pj_uang_muka_setujui',
        body: {
          'uangMukaId': advances[i]!['id'],
          'keterangan': 'LPJ uang muka berdasarkan bukti transaksi sample UAT.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'ATK dan konsumsi kegiatan unit',
              'jumlah': 150000 + (i % 5) * 10000,
              'akun': expense['id'],
              'ppn': 0
            }
          ],
          'dikembalikan': 0,
          'tanggalStor': '2026-09-$day',
          'namaSponsor': '',
          'dariSponsor': 0,
          'statusDokumen': 'Pengajuan',
        },
      );
    }

    final bigCash = <int, Map<String, dynamic>>{};
    for (var i = 1; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final day = (1 + ((i - 1) % 4)).toString().padLeft(2, '0');
      final row = await ensureDocument(
        index: bigCashByName,
        name: '$_prefix-KB-$serial — Belanja Operasional',
        saveAction: 'kas_besar_simpan',
        approveAction: 'kas_besar_setujui',
        body: {
          'satuanKerjaId': satker['id'],
          'jenisKasBesarId': bigCashType['id'],
          'ambilDariKasKecil': false,
          'kasKecilId': 0,
          'tanggal': '2026-09-$day',
          'keterangan': 'Pembayaran kebutuhan operasional sample UAT.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Pemeliharaan dan perlengkapan operasional',
              'jumlah': 200000 + (i % 4) * 25000,
              'akun': expense['id']
            }
          ],
          'statusDokumen': 'Pengajuan',
        },
      );
      await submit('kas_besar', row);
      bigCash[i] = row;
    }
    await realizeBatch('KAS-BESAR', '$_prefix-KB-');
    for (var i = 1; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final day = (1 + ((i - 1) % 4)).toString().padLeft(2, '0');
      await ensureDocument(
        index: bigCashLpjByName,
        name: '$_prefix-LPJ-KB-$serial — Bukti Belanja',
        saveAction: 'pj_kas_besar_simpan',
        approveAction: 'pj_kas_besar_setujui',
        body: {
          'kasBesarId': bigCash[i]!['id'],
          'keterangan': 'LPJ kas besar berdasarkan nota sample UAT.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Pemeliharaan dan perlengkapan operasional',
              'jumlah': 200000 + (i % 4) * 25000,
              'akun': expense['id']
            }
          ],
          'dikembalikan': 0,
          'tanggalStor': '2026-09-$day',
          'namaSponsor': '',
          'dariSponsor': 0,
          'statusDokumen': 'Pengajuan',
        },
      );
    }

    for (var i = 1; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final day = (1 + ((i - 1) % 4)).toString().padLeft(2, '0');
      final row = await ensureDocument(
        index: pettyByName,
        name: '$_prefix-KK-$serial — Pengeluaran Harian',
        saveAction: 'kas_kecil_simpan',
        approveAction: 'kas_kecil_setujui',
        body: {
          'satuanKerjaId': satker['id'],
          'jenisKasKecilId': pettyType['id'],
          'tanggal': '2026-09-$day',
          'keterangan': 'Parkir, kurir, dan konsumsi ringan sample UAT.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Pengeluaran operasional harian',
              'jumlah': 25000 + (i % 5) * 5000,
              'akun': expense['id']
            }
          ],
          'statusDokumen': 'Pengajuan',
        },
      );
      final refill = await ensureDocument(
        index: refillByName,
        name: '$_prefix-GANTI-KK-$serial — Pengisian Kembali',
        saveAction: 'penggantian_kas_kecil_simpan',
        approveAction: 'penggantian_kas_kecil_setujui',
        body: {
          'satuanKerjaId': satker['id'],
          'kasKecilId': row['id'],
          'keterangan': 'Penggantian kas kecil sesuai bukti sample UAT.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Pengisian kembali kas kecil',
              'jumlah': 25000 + (i % 5) * 5000,
              'akun': expense['id']
            }
          ],
          'statusDokumen': 'Pengajuan',
        },
      );
      await submit('penggantian_kas_kecil', refill);
      if (i == 1 || i % 10 == 0 || i == volume) {
        // ignore: avoid_print
        print('FIN_$i=${jsonEncode({
              'uangMukaId': advances[i]!['id'],
              'kasBesarId': bigCash[i]!['id'],
              'kasKecilId': row['id']
            })}');
      }
    }
    await realizeBatch('KAS-KECIL', '$_prefix-GANTI-KK-');

    String? reimbursementBlocker;
    try {
      final reimbursementOptions = await call('reimbursement_opsi');
      final types =
          ((reimbursementOptions['jenisReimbursement'] as List?) ?? const [])
              .whereType<Map>()
              .toList();
      final expenseTypes =
          ((reimbursementOptions['jenisPengeluaran'] as List?) ?? const [])
              .whereType<Map>()
              .toList();
      final people = rows(await call('reimbursement_cari_pegawai'));
      if (types.isNotEmpty && expenseTypes.isNotEmpty && people.isNotEmpty) {
        final reimbursementType = types.firstWhere(
          (e) => e['menggunakanAnggaran'] != true,
          orElse: () => types.first,
        );
        for (var i = 1; i <= volume; i++) {
          final serial = i.toString().padLeft(3, '0');
          final name = '$_prefix-REIMBURSEMENT-$serial — Perjalanan Dinas';
          final row = await ensureDocument(
            index: reimbursementByName,
            name: name,
            saveAction: 'reimbursement_simpan',
            approveAction: 'reimbursement_setujui',
            body: {
              'satuanKerjaId': satker['id'],
              'jenisReimbursementId': reimbursementType['id'],
              'pegawaiId': people.first['id'],
              // Server mewajibkan atasan untuk jejak persetujuan. Data demo
              // memakai pegawai yang sama agar seed tetap deterministik.
              'atasanId': people.first['id'],
              'tanggalPengeluaran': '2026-09-04',
              'keterangan':
                  'Reimbursement transportasi dan parkir sample volume UAT.',
              'rincian': [
                {
                  'key': 1,
                  'uraian': 'Transportasi operasional perjalanan dinas',
                  'jumlah': 50000 + (i % 10) * 5000,
                  'akun': expenseTypes.first['akunId'] ?? expense['id'],
                  'jenisPengeluaran': expenseTypes.first['id'],
                }
              ],
              'statusDokumen': 'Diajukan',
            },
          );
          await submit('reimbursement', row);
        }
        await realizeBatch('REIMBURSEMENT', '$_prefix-REIMBURSEMENT-');
      }
    } catch (e) {
      reimbursementBlocker = '$e';
    }

    final audit = <String, dynamic>{
      'createdFlowsThisRun': createdFlows,
      'reimbursementBlocker': reimbursementBlocker,
    };
    for (final action in [
      'uang_muka_daftar',
      'pj_uang_muka_daftar',
      'kas_besar_daftar',
      'pj_kas_besar_daftar',
      'kas_kecil_daftar',
      'penggantian_kas_kecil_daftar',
      'reimbursement_daftar',
    ]) {
      final data = rows(await call(action));
      audit[action] =
          data.where((e) => '${e['nama']}'.startsWith(_prefix)).length;
    }
    final journal = await call('draft_jurnal_ringkasan', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
    });
    audit['kategori'] = ((journal['data'] as List?) ?? const [])
        .whereType<Map>()
        .where((e) => const {
              'uang_muka',
              'pj_uang_muka',
              'kas_besar',
              'pj_kas_besar',
              'kas_kecil',
              'penggantian_kas_kecil',
              'reimbursement',
            }.contains('${e['kunci']}'))
        .map((e) => {
              'kunci': e['kunci'],
              'nama': e['nama'],
              'draft': e['draft'],
              'posting': e['posting'],
            })
        .toList();
    // ignore: avoid_print
    print('FIN_AUDIT=${jsonEncode(audit)}');
  });
}
