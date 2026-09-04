import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lengkapi master dan data sampel Keuangan', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Seed-Keuangan',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>> call(String action,
        [Map<String, dynamic>? body]) async {
      final result = await ApiClient.instance.aksi(action, body ?? const {});
      // ignore: avoid_print
      print('SEED_$action=${jsonEncode({
            for (final k in [
              'id',
              'kode',
              'message',
              'description',
              'jumlahJurnal'
            ])
              if (result.containsKey(k)) k: result[k],
          })}');
      return result;
    }

    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
        // ignore: avoid_print
        print('STEP_OK=$name');
      } catch (e) {
        // Keep seeding independent flows so one data constraint does not leave all
        // other Finance menus empty.
        // ignore: avoid_print
        print('STEP_GALAT=$name :: $e'
            '${e is ApiException ? '\n${e.teknis}' : ''}');
      }
    }

    List<Map<String, dynamic>> rows(Map<String, dynamic> response) =>
        ((response['data'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    final accountResponse = await call('akun_list', {'limit': 5000});
    final accounts = rows(accountResponse)
        .where((a) => a['leaf'] == true)
        .toList(growable: false);

    String normal(Object? value) => '${value ?? ''}'
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .trim();

    const synonyms = <String, List<String>>{
      'BBM': ['BBM', 'BENSIN', 'TRANSPORT'],
      'BENSIN': ['BBM', 'BENSIN', 'TRANSPORT'],
      'SOLAR': ['BBM', 'BENSIN', 'TRANSPORT'],
      'PARKIR': ['PARKIR', 'TRANSPORT', 'PERJALANAN'],
      'TOL': ['TOL', 'TRANSPORT', 'PERJALANAN'],
      'ATK': ['ATK', 'ALAT TULIS', 'KANTOR'],
      'CETAK': ['CETAK', 'PENGGANDAAN', 'KANTOR'],
      'FOTOCOPY': ['CETAK', 'PENGGANDAAN', 'KANTOR'],
      'INTERNET': ['INTERNET', 'TELEPON', 'KOMUNIKASI'],
      'TELEPON': ['TELEPON', 'KOMUNIKASI'],
      'LISTRIK': ['LISTRIK', 'UTILITAS'],
      'AIR': ['AIR', 'UTILITAS'],
      'GALON': ['KONSUMSI', 'MINUM', 'AIR'],
      'MAKAN': ['KONSUMSI', 'MAKAN', 'RAPAT'],
      'MINUM': ['KONSUMSI', 'MINUM', 'RAPAT'],
      'KONSUMSI': ['KONSUMSI', 'MAKAN', 'RAPAT'],
      'HOTEL': ['PENGINAPAN', 'PERJALANAN'],
      'PENGINAPAN': ['PENGINAPAN', 'PERJALANAN'],
      'SEMINAR': ['PELATIHAN', 'PENDIDIKAN', 'SEMINAR'],
      'PELATIHAN': ['PELATIHAN', 'PENDIDIKAN'],
      'BUKU': ['BUKU', 'PENDIDIKAN'],
      'SERVIS': ['PEMELIHARAAN', 'PERBAIKAN', 'SERVIS'],
      'PERBAIKAN': ['PEMELIHARAAN', 'PERBAIKAN'],
      'KEBERSIHAN': ['KEBERSIHAN', 'RUMAH TANGGA'],
      'MEDIS': ['KESEHATAN', 'MEDIS'],
      'OBAT': ['KESEHATAN', 'OBAT'],
      'SEWA': ['SEWA'],
      'BANK': ['BANK', 'ADMINISTRASI'],
      'ADMIN': ['ADMINISTRASI', 'UMUM'],
      'LAIN': ['LAIN', 'UMUM'],
    };

    Map<String, dynamic> pickAccount(String label) {
      final words =
          normal(label).split(' ').where((w) => w.length >= 3).toSet();
      Map<String, dynamic>? best;
      var bestScore = -1;
      for (final account in accounts) {
        final name = normal(account['nama']);
        final code = '${account['kode'] ?? ''}';
        // Expenses and operating-cost accounts are the safest candidates for
        // reimbursement/detail categories. Keep asset/liability accounts out.
        final expenseLike = code.startsWith('5') ||
            code.startsWith('6') ||
            code.startsWith('7') ||
            name.contains('BIAYA') ||
            name.contains('BEBAN');
        if (!expenseLike) continue;
        var score = 0;
        for (final word in words) {
          if (name.contains(word)) score += 7;
          for (final alias in synonyms[word] ?? const <String>[]) {
            if (name.contains(alias)) score += 4;
          }
        }
        if (name.contains('ADMINISTRASI') && name.contains('UMUM')) score += 1;
        if (score > bestScore) {
          bestScore = score;
          best = account;
        }
      }
      best ??= accounts.firstWhere(
        (a) => normal(a['nama']).contains('BIAYA SEWA'),
        orElse: () => accounts.first,
      );
      return best;
    }

    final expenseAtk = pickAccount('ATK alat tulis kantor');
    final expenseTransport = pickAccount('BBM bensin transport perjalanan');
    final expenseConsumption = pickAccount('Konsumsi rapat makan minum');
    final expenseMaintenance = pickAccount('Pemeliharaan servis perbaikan');
    final expenseAdmin = pickAccount('Administrasi umum lainnya');

    // ----------------------------------------------------------------- master
    await step('pemetaan seluruh master Keuangan', () async {
      final opsi = await call('master_keuangan_opsi');
      final metas = ((opsi['tipe'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      int updated = 0;
      for (final meta in metas) {
        final type = '${meta['tipe']}';
        final current =
            rows(await call('master_keuangan_daftar', {'tipe': type}));
        for (final row in current) {
          final body = <String, dynamic>{
            'tipe': type,
            'id': row['id'],
            'nama': row['nama'],
            'kode': row['kode'] ?? '',
            'keterangan': row['keterangan'] ?? '',
            'aktif': row['aktif'] != false,
            if (row['satuanKerjaId'] != null)
              'satuanKerjaId': row['satuanKerjaId'],
            if (type == 'jenis_reimbursement')
              'menggunakanAnggaran': row['menggunakanAnggaran'] == true,
          };
          bool needsSave = false;
          for (final field in ((meta['medanAkun'] as List?) ?? const [])) {
            final key = '${(field as Map)['kunci']}';
            var value = row[key];
            if (value == null) {
              if (type == 'jenis_kas_besar' && key == 'akunKeduaId') {
                // Clearing account used between cash disbursement and its LPJ.
                final um = rows(await call(
                    'master_keuangan_daftar', {'tipe': 'jenis_uang_muka'}));
                value = um.isEmpty ? expenseAdmin['id'] : um.first['akunId'];
              } else if (type == 'jenis_reimbursement' &&
                  row['menggunakanAnggaran'] == true) {
                // The selected budget supplies the account for this variant.
                value = null;
              } else {
                value = pickAccount('${row['nama']}')['id'];
              }
              if (value != null) needsSave = true;
            }
            if (value != null) body[key] = value;
          }
          if (needsSave) {
            await call('master_keuangan_simpan', body);
            updated++;
          }
        }
      }
      // ignore: avoid_print
      print('MASTER_KEUANGAN_DIPERBARUI=$updated');
    });

    await step('penomoran seluruh dokumen Keuangan', () async {
      var templates = rows(await call('nomor_surat_keuangan_templat_daftar'));
      var template = templates.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t?['nama'] == 'Standar Dokumen Keuangan eBisnis',
            orElse: () => null,
          );
      if (template == null) {
        final segments = <Map<String, dynamic>>[
          {'jenis': 'Kata Statis', 'tanda': 'FIN/'},
          {'jenis': 'Nomor Urut', 'tanda': '/'},
          {'jenis': 'Bulan Romawi', 'tanda': '/'},
          {'jenis': 'Tahun', 'tanda': ''},
          for (var i = 4; i < 10; i++) {'jenis': 'Kosong', 'tanda': ''},
        ];
        final created = await call('nomor_surat_keuangan_templat_simpan', {
          'nama': 'Standar Dokumen Keuangan eBisnis',
          'keterangan':
              'Penomoran konsisten untuk data demonstrasi dan UAT Keuangan.',
          'aktif': true,
          'jumlahNolDepan': 4,
          'resetTiapTahun': true,
          'resetTiapBulan': false,
          'urutBerdasarkanNomor': true,
          'urutBerdasarkanKelompok': false,
          'gunakanIndexUrut': false,
          'nomorIndex': 1,
          'segmen': segments,
        });
        template = {'id': created['id']};
      }
      final flows = rows(await call('nomor_surat_keuangan_daftar'));
      for (final flow in flows) {
        if (flow['nomorSuratId'] != template['id']) {
          await call('nomor_surat_keuangan_pasang', {
            'alurId': flow['id'],
            'nomorSuratId': template['id'],
          });
        }
      }
    });

    final financeOptions = await call('uang_muka_opsi');
    final satkers = ((financeOptions['satuanKerja'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final satker = satkers.firstWhere(
      (s) => normal(s['nama']).contains('YAYASAN UNIVERSITAS PGRI ARGOPURO'),
      orElse: () => satkers.first,
    );
    final advanceTypes =
        ((financeOptions['jenisUangMuka'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final advanceType = advanceTypes.first;

    Future<Map<String, dynamic>> findOrCreate({
      required String listAction,
      required String saveAction,
      required String name,
      required Map<String, dynamic> body,
    }) async {
      var list = rows(await call(listAction));
      var found = list.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['nama'] == name,
            orElse: () => null,
          );
      if (found != null) return found;
      final created = await call(saveAction, {'nama': name, ...body});
      list = rows(await call(listAction));
      found = list.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == created['id'] || r?['nama'] == name,
            orElse: () => null,
          );
      if (found == null) {
        throw StateError('$name tidak kembali pada $listAction');
      }
      return found;
    }

    Future<Map<String, dynamic>> refresh(String listAction, String name) async {
      final list = rows(await call(listAction));
      return list.firstWhere((r) => r['nama'] == name);
    }

    Future<Map<String, dynamic>> approve({
      required String prefix,
      required String name,
    }) async {
      var row = await refresh('${prefix}_daftar', name);
      if ('${row['statusDokumen']}' != 'Disetujui') {
        await call('${prefix}_setujui', {
          'id': row['id'],
          'tanggalPersetujuan': '2026-09-04',
        });
        row = await refresh('${prefix}_daftar', name);
      }
      return row;
    }

    Future<void> submitToTransfer(
        String prefix, Map<String, dynamic> row) async {
      if (row['dpcAda'] != true) {
        await call('${prefix}_ajukan_transfer', {'id': row['id']});
      }
    }

    Future<void> processTransferFor(
        String sourceName, String processName) async {
      var processes = rows(await call('proses_transfer_daftar'));
      var process = processes.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p?['nama'] == processName,
            orElse: () => null,
          );
      if (process == null) {
        final candidates = rows(await call('proses_transfer_kandidat'));
        final selected = candidates
            .where((c) => '${c['nama']}'.contains(sourceName))
            .toList();
        if (selected.isEmpty) {
          throw StateError(
              'Kandidat transfer tidak ditemukan untuk $sourceName');
        }
        final paymentOptions = await call('proses_transfer_opsi');
        final methods =
            ((paymentOptions['caraPembayaran'] as List?) ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
        final method = methods.firstWhere(
          (m) => normal(m['nama']).contains('BCA'),
          orElse: () => methods.first,
        );
        final made = await call('proses_transfer_simpan', {
          'nama': processName,
          'keterangan':
              'Transfer data sampel UAT melalui rekening operasional.',
          'caraPembayaranId': method['id'],
          'tanggalPembuatan': '2026-09-04',
          'dptIds': selected.map((e) => e['id']).toList(),
        });
        process = {'id': made['id'], 'statusDokumen': 'Draft'};
      }
      if ('${process['statusDokumen']}' == 'Draft') {
        await call('proses_transfer_setujui', {
          'id': process['id'],
          'tanggalPersetujuan': '2026-09-04',
          'catatanPersetujuan': 'Disetujui untuk kebutuhan demonstrasi UAT.',
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
      processes = rows(await call('proses_transfer_daftar'));
      process = processes.firstWhere((p) => p['nama'] == processName);
      if ('${process['statusDokumen']}' != 'Terealisasi') {
        await call('proses_transfer_realisasikan', {
          'id': process['id'],
          'tanggalRealisasikan': '2026-09-04',
          'catatanRealisasi': 'Dana UAT telah direalisasikan.',
        });
      }
    }

    late Map<String, dynamic> mainAdvance;
    await step('uang muka lengkap hingga realisasi', () async {
      const name = 'UAT Sampel - Uang Muka Operasional September';
      mainAdvance = await findOrCreate(
        listAction: 'uang_muka_daftar',
        saveAction: 'uang_muka_simpan',
        name: name,
        body: {
          'keterangan':
              'Pembelian ATK, transportasi lokal, dan konsumsi rapat operasional.',
          'tanpaAnggaran': true,
          'ambilDariPr': false,
          'satuanKerjaId': satker['id'],
          'akunId': expenseAtk['id'],
          'workspaceId': 0,
          'jenisUangMukaId': advanceType['id'],
          'nilai': 2750000,
          'mulai': '2026-09-04',
          'sampai': '2026-09-08',
          'selesai': '2026-09-10',
          'statusDokumen': 'Pengajuan',
        },
      );
      mainAdvance = await approve(prefix: 'uang_muka', name: name);
      await submitToTransfer('uang_muka', mainAdvance);
      await processTransferFor(
          name, 'UAT Sampel - Transfer Uang Muka September');
      mainAdvance = await refresh('uang_muka_daftar', name);
    });

    await step('uang muka pengajuan sebagai data antrean', () async {
      await findOrCreate(
        listAction: 'uang_muka_daftar',
        saveAction: 'uang_muka_simpan',
        name: 'UAT Sampel - Uang Muka Pelatihan Tim',
        body: {
          'keterangan': 'Biaya registrasi pelatihan pelayanan pelanggan.',
          'tanpaAnggaran': true,
          'ambilDariPr': false,
          'satuanKerjaId': satker['id'],
          'akunId': pickAccount('Pelatihan seminar')['id'],
          'workspaceId': 0,
          'jenisUangMukaId': advanceType['id'],
          'nilai': 1800000,
          'mulai': '2026-09-15',
          'sampai': '2026-09-16',
          'selesai': '2026-09-18',
          'statusDokumen': 'Pengajuan',
        },
      );
    });

    await step('dana talangan lengkap hingga realisasi', () async {
      const name = 'UAT Sampel - Dana Talangan Operasional Mendesak';
      var row = await findOrCreate(
        listAction: 'dana_talangan_daftar',
        saveAction: 'dana_talangan_simpan',
        name: name,
        body: {
          'satuanKerjaId': satker['id'],
          'uangMukaId': mainAdvance['id'],
          'jenisUangMukaId': advanceType['id'],
          'nilai': 750000,
          'keterangan':
              'Talangan sementara sebelum pencairan biaya operasional.',
          'statusDokumen': 'Pengajuan',
        },
      );
      row = await approve(prefix: 'dana_talangan', name: name);
      await submitToTransfer('dana_talangan', row);
      await processTransferFor(name, 'UAT Sampel - Transfer Dana Talangan');
    });

    await step('pertanggungjawaban uang muka', () async {
      const name = 'UAT Sampel - LPJ Uang Muka Operasional September';
      await findOrCreate(
        listAction: 'pj_uang_muka_daftar',
        saveAction: 'pj_uang_muka_simpan',
        name: name,
        body: {
          'uangMukaId': mainAdvance['id'],
          'keterangan':
              'LPJ berdasarkan nota dan bukti pengeluaran operasional.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'ATK dan bahan cetak administrasi',
              'jumlah': 1250000,
              'akun': expenseAtk['id'],
              'ppn': 0,
            },
            {
              'key': 2,
              'uraian': 'Transportasi dan pengiriman dokumen',
              'jumlah': 700000,
              'akun': expenseTransport['id'],
              'ppn': 0,
            },
            {
              'key': 3,
              'uraian': 'Konsumsi rapat koordinasi',
              'jumlah': 600000,
              'akun': expenseConsumption['id'],
              'ppn': 0,
            },
          ],
          'dikembalikan': 200000,
          'tanggalStor': '2026-09-10',
          'namaSponsor': '',
          'dariSponsor': 0,
          'statusDokumen': 'Pengajuan',
        },
      );
      await approve(prefix: 'pj_uang_muka', name: name);
    });

    late Map<String, dynamic> mainCash;
    await step('kas besar lengkap hingga realisasi', () async {
      final opts = await call('kas_besar_opsi');
      final kinds = ((opts['jenisKasBesar'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final kind = kinds.firstWhere(
        (k) => normal(k['nama']).contains('YAYASAN'),
        orElse: () => kinds.first,
      );
      const name = 'UAT Sampel - Kas Besar Perawatan Fasilitas';
      mainCash = await findOrCreate(
        listAction: 'kas_besar_daftar',
        saveAction: 'kas_besar_simpan',
        name: name,
        body: {
          'satuanKerjaId': satker['id'],
          'jenisKasBesarId': kind['id'],
          'ambilDariKasKecil': false,
          'kasKecilId': 0,
          'tanggal': '2026-09-04',
          'keterangan': 'Perawatan fasilitas dan perangkat operasional.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Servis pendingin ruangan',
              'jumlah': 1850000,
              'akun': expenseMaintenance['id'],
            },
            {
              'key': 2,
              'uraian': 'Penggantian lampu dan instalasi',
              'jumlah': 650000,
              'akun': pickAccount('Listrik utilitas')['id'],
            },
          ],
          'statusDokumen': 'Pengajuan',
        },
      );
      mainCash = await approve(prefix: 'kas_besar', name: name);
      await submitToTransfer('kas_besar', mainCash);
      await processTransferFor(name, 'UAT Sampel - Transfer Kas Besar');
      mainCash = await refresh('kas_besar_daftar', name);
    });

    await step('pertanggungjawaban kas besar', () async {
      const name = 'UAT Sampel - LPJ Kas Besar Perawatan Fasilitas';
      await findOrCreate(
        listAction: 'pj_kas_besar_daftar',
        saveAction: 'pj_kas_besar_simpan',
        name: name,
        body: {
          'kasBesarId': mainCash['id'],
          'keterangan': 'LPJ lengkap dengan nota servis dan material.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Jasa servis pendingin ruangan',
              'jumlah': 1800000,
              'akun': expenseMaintenance['id'],
            },
            {
              'key': 2,
              'uraian': 'Material listrik dan lampu',
              'jumlah': 600000,
              'akun': pickAccount('Listrik utilitas')['id'],
            },
          ],
          'dikembalikan': 100000,
          'tanggalStor': '2026-09-11',
          'namaSponsor': '',
          'dariSponsor': 0,
          'statusDokumen': 'Pengajuan',
        },
      );
      await approve(prefix: 'pj_kas_besar', name: name);
    });

    late Map<String, dynamic> pettyCash;
    await step('kas kecil dan penggantian', () async {
      final opts = await call('kas_kecil_opsi');
      final kinds = ((opts['jenisKasKecil'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final kind = kinds.firstWhere(
        (k) => normal(k['nama']).contains('YAYASAN'),
        orElse: () => kinds.first,
      );
      const pettyName = 'UAT Sampel - Kas Kecil Operasional Harian';
      pettyCash = await findOrCreate(
        listAction: 'kas_kecil_daftar',
        saveAction: 'kas_kecil_simpan',
        name: pettyName,
        body: {
          'satuanKerjaId': satker['id'],
          'jenisKasKecilId': kind['id'],
          'tanggal': '2026-09-04',
          'keterangan': 'Pengeluaran kecil harian dengan bukti nota.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Parkir dan tol pengantaran dokumen',
              'jumlah': 85000,
              'akun': expenseTransport['id'],
            },
            {
              'key': 2,
              'uraian': 'Air minum rapat',
              'jumlah': 120000,
              'akun': expenseConsumption['id'],
            },
            {
              'key': 3,
              'uraian': 'Perlengkapan kebersihan',
              'jumlah': 195000,
              'akun': pickAccount('Kebersihan rumah tangga')['id'],
            },
          ],
          'statusDokumen': 'Pengajuan',
        },
      );
      pettyCash = await approve(prefix: 'kas_kecil', name: pettyName);

      const refillName = 'UAT Sampel - Penggantian Kas Kecil Mingguan';
      var refill = await findOrCreate(
        listAction: 'penggantian_kas_kecil_daftar',
        saveAction: 'penggantian_kas_kecil_simpan',
        name: refillName,
        body: {
          'satuanKerjaId': satker['id'],
          'kasKecilId': pettyCash['id'],
          'keterangan': 'Penggantian atas kas kecil operasional harian.',
          'rincian': pettyCash['rincian'],
          'statusDokumen': 'Pengajuan',
        },
      );
      refill = await approve(prefix: 'penggantian_kas_kecil', name: refillName);
      await submitToTransfer('penggantian_kas_kecil', refill);
      await processTransferFor(
          refillName, 'UAT Sampel - Transfer Penggantian Kas Kecil');
    });

    await step('reimbursement pegawai lengkap hingga realisasi', () async {
      final opts = await call('reimbursement_opsi');
      final types = ((opts['jenisReimbursement'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final type = types.firstWhere(
        (t) => t['menggunakanAnggaran'] != true,
        orElse: () => types.first,
      );
      final people = rows(await call('reimbursement_cari_pegawai'));
      if (people.isEmpty) throw StateError('Data pegawai belum tersedia');
      final employee = people.first;
      final expenses = ((opts['jenisPengeluaran'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final expenseType = expenses.firstWhere(
        (e) => normal(e['nama']).contains('BBM'),
        orElse: () => expenses.first,
      );
      const name = 'UAT Sampel - Reimbursement Kunjungan Operasional';
      var row = await findOrCreate(
        listAction: 'reimbursement_daftar',
        saveAction: 'reimbursement_simpan',
        name: name,
        body: {
          'satuanKerjaId': satker['id'],
          'jenisReimbursementId': type['id'],
          'pegawaiId': employee['id'],
          'tanggalPengeluaran': '2026-09-03',
          'keterangan': 'Penggantian biaya perjalanan kunjungan operasional.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'BBM perjalanan dinas lokal',
              'jumlah': 350000,
              'akun': expenseType['akunId'] ?? expenseTransport['id'],
              'jenisPengeluaran': expenseType['id'],
            },
            {
              'key': 2,
              'uraian': 'Parkir lokasi kunjungan',
              'jumlah': 50000,
              'akun': expenseTransport['id'],
              'jenisPengeluaran': expenseType['id'],
            },
          ],
          'statusDokumen': 'Diajukan',
        },
      );
      row = await approve(prefix: 'reimbursement', name: name);
      await submitToTransfer('reimbursement', row);
      await processTransferFor(
          name, 'UAT Sampel - Transfer Reimbursement Pegawai');

      await findOrCreate(
        listAction: 'reimbursement_daftar',
        saveAction: 'reimbursement_simpan',
        name: 'UAT Sampel - Reimbursement ATK Menunggu Persetujuan',
        body: {
          'satuanKerjaId': satker['id'],
          'jenisReimbursementId': type['id'],
          'pegawaiId': employee['id'],
          'tanggalPengeluaran': '2026-09-04',
          'keterangan': 'Penggantian pembelian ATK mendesak.',
          'rincian': [
            {
              'key': 1,
              'uraian': 'Kertas, tinta, dan map arsip',
              'jumlah': 475000,
              'akun': expenseAtk['id'],
              'jenisPengeluaran': expenseType['id'],
            },
          ],
          'statusDokumen': 'Diajukan',
        },
      );
    });

    // Post every available Finance journal once, then keep the pending documents
    // created above so screenshots contain both completed and in-progress states.
    await step('posting draft jurnal Keuangan', () async {
      final summary = rows(await call('draft_jurnal_ringkasan', {
        'mulai': '2026-08-01',
        'sampai': '2026-09-30',
      }));
      const financeKeys = {
        'uang_muka',
        'pj_uang_muka',
        'kas_kecil',
        'kas_besar',
        'pj_kas_besar',
        'penggantian_kas_kecil',
        'dana_talangan',
        'reimbursement',
        'pengajuan_transfer',
      };
      for (final item in summary) {
        if (financeKeys.contains('${item['kunci']}') &&
            ((item['draft'] as num?)?.toInt() ?? 0) > 0 &&
            item['bisaPosting'] == true &&
            item['bolehPosting'] != false) {
          await call('draft_jurnal_posting', {
            'nama': item['nama'],
            'mulai': '2026-08-01',
            'sampai': '2026-09-30',
          });
        }
      }
    });

    await step('setoran pajak sampel', () async {
      final taxes = await call('pengadaan_pajak_terutang');
      final due = rows(taxes);
      final withPpn = due.where((r) => ((r['ppn'] as num?) ?? 0) > 0).toList();
      final paid = rows(await call('pengadaan_pajak_daftar'));
      final existing = paid.any((r) => '${r['ntpn']}' == 'UAT202609040001');
      if (!existing && withPpn.isNotEmpty) {
        await call('pengadaan_pajak_setor', {
          'jenis': 'PPN',
          'ntpn': 'UAT202609040001',
          'tanggalSetor': '04-09-2026',
          'npwp': '00.000.000.0-000.000',
          'namaWp': 'eBisnis Demo',
          'keterangan': 'Setoran PPN data sampel UAT.',
          'detail': [
            for (final row in withPpn)
              if (row['sumber'] == 'BAST')
                {'bast_detail_id': row['bast_detail_id']}
              else
                {'detail_id': row['detail_id']},
          ],
        });
      }
    });

    final finalSummary = await call('draft_jurnal_ringkasan', {
      'mulai': '2026-08-01',
      'sampai': '2026-09-30',
    });
    // ignore: avoid_print
    print('RINGKASAN_AKHIR=${jsonEncode({
          'draft': finalSummary['draft'],
          'posting': finalSummary['posting'],
          'closing': finalSummary['closing'],
        })}');
  });
}
