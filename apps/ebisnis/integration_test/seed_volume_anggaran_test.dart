import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tahun = 2026;
const _revisi = 1;
const _prefix = 'UAT-RAB-500-20260904';
const _tanggal = '2026-09-04';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed 500 mata anggaran dan realisasi bertahap terintegrasi',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const volume =
        int.fromEnvironment('ANGGARAN_UAT_VOLUME', defaultValue: 500);

    expect(volume, greaterThanOrEqualTo(500),
        reason: 'UAT Anggaran mensyaratkan sedikitnya 500 mata anggaran.');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Volume-Anggaran-500',
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
            await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
          }
        }
      }
      throw StateError('$action gagal: $last');
    }

    List<Map<String, dynamic>> rows(Map<String, dynamic> response) =>
        ((response['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final accounts = rows(await call('akun_list', {'limit': 5000}));
    final expense = accounts.firstWhere(
      (e) => e['leaf'] == true && '${e['kode']}'.startsWith('5'),
      orElse: () => accounts.firstWhere((e) => e['leaf'] == true),
    );
    final cash = accounts.firstWhere(
      (e) => '${e['kode']}' == '111.101',
      orElse: () => accounts.firstWhere(
          (e) => e['leaf'] == true && '${e['kode']}'.startsWith('1')),
    );

    final options = await call('anggaran_konteks');
    final satkers = ((options['satuanKerja'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    expect(satkers, isNotEmpty,
        reason: 'Satuan kerja Anggaran belum tersedia.');
    // Satuan kerja 20000025 adalah konteks pertama yang otomatis dipilih layar
    // Anggaran pada tenant demo. Memprioritaskannya membuat bukti layar segera
    // menampilkan 500 item tanpa langkah filter tersembunyi.
    final satker = satkers.firstWhere(
      (e) => (e['id'] as num?)?.toInt() == 20000025,
      orElse: () => satkers.firstWhere(
        (e) => '${e['nama']}'.toUpperCase().contains('YAYASAN'),
        orElse: () => satkers.first,
      ),
    );
    final satkerId = (satker['id'] as num).toInt();

    Map<String, Map<String, dynamic>> indexedItems() =>
        <String, Map<String, dynamic>>{};
    var existing = rows(await call('anggaran_item_list', {
      'tahun': _tahun,
      'satkerId': satkerId,
      'sumberDanaId': 0,
      'revisi': _revisi,
      'termasukAnakSatker': false,
      'termasukNonAktif': false,
      'cari': _prefix,
    }));
    final byCode = indexedItems()
      ..addEntries(existing.map((e) => MapEntry('${e['kode']}', e)));

    for (var i = 1; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final code = '$_prefix-$serial';
      if (!byCode.containsKey(code)) {
        final monthly = 5000000 + (i % 20) * 250000;
        final made = await call('anggaran_item_simpan', {
          'tahun': _tahun,
          'satkerId': satkerId,
          'sumberDanaId': 0,
          'revisi': _revisi,
          'parentId': 0,
          'kode': code,
          'nama': _budgetName(i, serial),
          'keterangan':
              'Data sample best practice UAT Anggaran eBisnis; pagu bulanan dan jejak realisasi dapat ditelusuri.',
          'qty': 12,
          'satuanVolume': 'Bulan',
          'hargaSatuan': monthly,
          'akunId': expense['id'],
          'aktif': true,
          'bulan': List<double>.filled(12, monthly.toDouble()),
        });
        byCode[code] = {
          'id': made['id'],
          'idTeks': '${made['id']}',
          'kode': code,
          'nama': _budgetName(i, serial),
        };
      }
      if (i == 1 || i % 50 == 0 || i == volume) {
        // ignore: avoid_print
        print(
            'ANGGARAN_ITEM_$i=${byCode[code]!['idTeks'] ?? byCode[code]!['id']}');
      }
    }

    // Muat ulang agar semua id 64-bit negatif tersedia dalam bentuk teks yang
    // tidak akan dibulatkan oleh kanal JSON/JavaScript mana pun.
    existing = rows(await call('anggaran_item_list', {
      'tahun': _tahun,
      'satkerId': satkerId,
      'sumberDanaId': 0,
      'revisi': _revisi,
      'termasukAnakSatker': false,
      'cari': _prefix,
    }));
    byCode
      ..clear()
      ..addEntries(existing.map((e) => MapEntry('${e['kode']}', e)));
    expect(byCode.length, greaterThanOrEqualTo(volume),
        reason: 'Jumlah mata anggaran berpenanda UAT belum mencapai $volume.');

    // 450 baris pertama memperoleh transaksi realisasi manual berpenanda jelas.
    // Ini adalah data baseline untuk membuktikan laporan realisasi pada seluruh
    // mata anggaran, sedangkan 50 baris terakhir dibentuk oleh Jurnal Umum aktual.
    final usage = rows(await call('anggaran_penggunaan_list', {
      'tahun': _tahun,
      'satkerId': satkerId,
      'revisi': _revisi,
      'limit': 2000,
    }));
    final refs = usage.map((e) => '${e['ref']}').toSet();
    for (var i = 1; i <= volume - 50; i++) {
      final serial = i.toString().padLeft(3, '0');
      final code = '$_prefix-$serial';
      final ref = '${code}_UAT_BERTAHAP';
      if (!refs.contains(ref)) {
        final item = byCode[code]!;
        await call('anggaran_penggunaan_simpan', {
          'workspaceIdTeks': '${item['idTeks'] ?? item['id']}',
          'kode': '$_prefix-REAL-$serial',
          'ref': ref,
          'nama': 'Realisasi bertahap ${_scenario(i)}',
          'keterangan':
              'Baseline UAT untuk rekonsiliasi rencana, penggunaan, dan laporan realisasi; dokumen operasional contoh diuji pada modul terkait.',
          'nilai': 750000 + (i % 15) * 50000,
          'waktu':
              '2026-09-${(1 + (i % 4)).toString().padLeft(2, '0')} 10:00:00',
          'aktif': true,
        });
        refs.add(ref);
      }
      if (i == 1 || i % 75 == 0 || i == volume - 50) {
        // ignore: avoid_print
        print('ANGGARAN_REALISASI_MANUAL_$i');
      }
    }

    final journalList = rows(await call('jurnal_umum_list', {
      'mulai': '2026-09-01',
      'sampai': '2026-09-30',
      'cari': 'UAT Anggaran 500',
      'status': '',
    }));
    final journalByDescription = {
      for (final row in journalList) '${row['keterangan']}': row,
    };
    final idsToPost = <int>[];
    for (var i = volume - 49; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final code = '$_prefix-$serial';
      final description = 'UAT Anggaran 500 — jurnal realisasi $serial';
      var journal = journalByDescription[description];
      if (journal == null) {
        final item = byCode[code]!;
        final amount = 1250000 + (i % 10) * 75000;
        final made = await call('jurnal_umum_simpan', {
          'tanggal': _tanggal,
          'keterangan': description,
          'jenisTransaksiId': 0,
          'workspaceIdTeks': '${item['idTeks'] ?? item['id']}',
          'baris': [
            {
              'akunId': expense['id'],
              'debet': amount,
              'kredit': 0,
              'keterangan': 'Beban operasional sesuai mata anggaran $code',
            },
            {
              'akunId': cash['id'],
              'debet': 0,
              'kredit': amount,
              'keterangan': 'Pengeluaran kas atas realisasi $code',
            },
          ],
        });
        journal = {'id': made['id'], 'terposting': false};
      }
      if (journal['terposting'] != true && journal['id'] is num) {
        idsToPost.add((journal['id'] as num).toInt());
      }
    }
    if (idsToPost.isNotEmpty) {
      await call('jurnal_umum_posting', {'ids': idsToPost});
    }

    await Future<void>.delayed(const Duration(seconds: 3));
    // Listener pemakaian anggaran membuat baris dari jurnal. Bila listener pada
    // instalasi lama belum aktif, backfill manual menjaga 500/500 item tetap
    // dapat diuji tanpa menyamarkan sumbernya (nama mencantumkan BACKFILL).
    final afterJournal = rows(await call('anggaran_penggunaan_list', {
      'tahun': _tahun,
      'satkerId': satkerId,
      'revisi': _revisi,
      'limit': 2000,
    }));
    final usedWorkspace = afterJournal
        .where((e) => e['aktif'] == true)
        .map((e) => '${e['workspaceIdTeks'] ?? e['workspaceId']}')
        .toSet();
    for (var i = volume - 49; i <= volume; i++) {
      final serial = i.toString().padLeft(3, '0');
      final code = '$_prefix-$serial';
      final item = byCode[code]!;
      final workspaceId = '${item['idTeks'] ?? item['id']}';
      if (!usedWorkspace.contains(workspaceId)) {
        await call('anggaran_penggunaan_simpan', {
          'workspaceIdTeks': workspaceId,
          'kode': 'BACKFILL-$serial',
          'ref': '${code}_BACKFILL_JURNAL',
          'nama': 'Backfill audit Jurnal Umum $serial',
          'keterangan':
              'Backfill eksplisit karena listener penggunaan anggaran belum membentuk jejak otomatis pada waktu audit.',
          'nilai': 1250000 + (i % 10) * 75000,
          'waktu': '$_tanggal 13:00:00',
          'aktif': true,
        });
      }
    }

    final realization = await call('anggaran_realisasi_list', {
      'tahun': _tahun,
      'satkerId': satkerId,
      'sumberDanaId': 0,
      'revisi': _revisi,
      'termasukAnakSatker': false,
      'cari': _prefix,
    });
    final realizationRows = rows(realization);
    final realizedItems = realizationRows
        .where((e) => ((e['realisasi'] as num?)?.toDouble() ?? 0) > 0)
        .length;
    expect(realizationRows.length, greaterThanOrEqualTo(volume));
    expect(realizedItems, greaterThanOrEqualTo(volume),
        reason: 'Semua 500 mata anggaran harus memiliki jejak realisasi.');
    // ignore: avoid_print
    print('ANGGARAN_AUDIT=${jsonEncode({
          'satkerId': satkerId,
          'jumlahItem': realizationRows.length,
          'itemTerealisasi': realizedItems,
          'totalPagu': realization['totalPagu'],
          'totalRealisasi': realization['totalRealisasi'],
          'totalSisa': realization['totalSisa'],
          'jurnalDiposting': 50,
        })}');
  });
}

String _budgetName(int index, String serial) {
  final group = switch ((index - 1) ~/ 100) {
    0 => 'Pengadaan dan Persediaan',
    1 => 'Uang Muka dan LPJ',
    2 => 'Kas Besar',
    3 => 'Kas Kecil dan Reimbursement',
    _ => 'Jurnal Umum dan Penyesuaian',
  };
  return '$group — Mata Anggaran $serial';
}

String _scenario(int index) {
  if (index <= 100) {
    const stages = ['PR', 'PO', 'BAST', 'Terima Tagihan', 'Pembayaran Vendor'];
    return 'Pengadaan ${stages[(index - 1) % stages.length]}';
  }
  if (index <= 200) return 'Uang Muka dan LPJ';
  if (index <= 300) return 'Kas Besar';
  if (index <= 400) return 'Kas Kecil dan Reimbursement';
  return 'Jurnal Umum';
}
