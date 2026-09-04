import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('repair dan audit relasi akun Kantin POS Kulakan',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    const apply = bool.fromEnvironment('POS_APPLY_KANTIN_ACCOUNT_MAPPING');
    const post = bool.fromEnvironment('POS_POST_KANTIN');

    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Repair-Akun-Kantin',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);
    await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': 1});

    Future<Map<String, dynamic>> call(
      String action,
      Map<String, dynamic> body,
    ) async {
      return Map<String, dynamic>.from(
        await ApiClient.instance.aksi(action, body),
      );
    }

    final accounts = await call('akun_list', {'limit': 2000});
    final accountRows = ((accounts['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    Map<String, dynamic> account(String code) => accountRows.firstWhere(
          (e) => '${e['kode']}'.replaceAll(',', '.') == code,
          orElse: () => throw StateError('Akun $code tidak ditemukan'),
        );

    final kas = account('111.101');
    final piutang = account('131.300');
    final persediaan = account('151.200');
    final utang = account('310.600');
    final pendapatan = account('410.900');
    final hpp = account('510.900');
    final mapping = {
      'kas': kas,
      'piutang': piutang,
      'persediaan': persediaan,
      'utang': utang,
      'pendapatan': pendapatan,
      'hpp': hpp,
    };
    // ignore: avoid_print
    print('KANTIN_ACCOUNT_SOURCE=${jsonEncode(mapping)}');

    if (apply) {
      // Pemetaan akun adalah tindakan online-only: server harus memvalidasi akun
      // daun, scope toko, hak admin, dan commit atomik sebelum UI menyatakan sukses.
      try {
        final applied = await call('pemetaan_akun_kantin_terapkan', {
          'tokoId': 1,
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
        print('KANTIN_ACCOUNT_SERVER_APPLY=${jsonEncode(applied)}');
      } catch (e) {
        // Server lama belum mengenal aksi massal; master yang sudah punya API
        // tetap dipetakan di bawah, sementara Master Aset menunggu deploy helper.
        // ignore: avoid_print
        print('KANTIN_ACCOUNT_SERVER_APPLY_UNAVAILABLE=$e');
        if (e is ApiException) {
          // ignore: avoid_print
          print('KANTIN_ACCOUNT_SERVER_APPLY_TECHNICAL=${e.teknis}');
        }
      }

      final shops = await call('toko_kelola_list', const {});
      final shop = ((shops['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .firstWhere((e) => (e['id'] as num?)?.toInt() == 1);
      await call('toko_kelola_simpan', {
        'id': 1,
        'kode': shop['kode'],
        'nama': shop['nama'],
        'keterangan': shop['keterangan'],
        'aktif': shop['aktif'],
        'boleh_melihat_toko_lain': shop['boleh_melihat_toko_lain'],
        'boleh_transaksi_stok_habis': shop['boleh_transaksi_stok_habis'],
        'toko_demo': shop['toko_demo'],
        'unit_usaha': ((shop['unit_usaha'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e['kode'])
            .toList(),
        'akun_kas_id': kas['id'],
        'akun_piutang_id': piutang['id'],
        'akun_modal_awal_id': shop['akun_modal_awal_id'],
        'akun_laba_ditahan_id': shop['akun_laba_ditahan_id'],
      });

      final kinds = await call('jenis_produk_list', {
        'keyword': 'Elektronik Ringan - Saus dan Kecap',
        'page': 1,
        'page_size': 100,
        'termasuk_nonaktif': true,
      });
      var mappedKindCount = 0;
      for (final raw
          in ((kinds['data'] as List?) ?? const []).whereType<Map>()) {
        final kind = Map<String, dynamic>.from(raw);
        if ('${kind['nama']}' != 'Elektronik Ringan - Saus dan Kecap') {
          continue;
        }
        await call('jenis_produk_simpan', {
          'id': kind['id'],
          'nama': kind['nama'],
          'keterangan': kind['keterangan'],
          'maksimalHarian': kind['maksimalHarian'],
          'defaultProduk': kind['defaultProduk'],
          'aktif': kind['aktif'],
          'akunPendapatanId': kind['akunPendapatanId'] ?? pendapatan['id'],
          'akunPpnKeluaranId': kind['akunPpnKeluaranId'],
          'akunHppId': kind['akunHppId'] ?? hpp['id'],
          'akunSelisihPersediaanId':
              kind['akunSelisihPersediaanId'] ?? hpp['id'],
          'akunReturPenjualanId': kind['akunReturPenjualanId'],
        });
        mappedKindCount++;
      }
      expect(mappedKindCount, 1,
          reason: 'Jenis Produk tepat untuk barang UAT Kantin tidak ditemukan');

      for (final supplierName in [
        'CV Sumber Pangan Nusantara',
        'Toko ABC',
      ]) {
        final suppliers = await call('penyedia_list_admin', {
          'keyword': supplierName,
          'page': 1,
          'page_size': 100,
        });
        for (final raw
            in ((suppliers['data'] as List?) ?? const []).whereType<Map>()) {
          final supplier = Map<String, dynamic>.from(raw);
          if ('${supplier['nama']}' != supplierName) continue;
          await call('penyedia_simpan', {
            ...supplier,
            'akunUtangId': utang['id'],
          });
        }
      }

      // Master Aset tidak boleh dipetakan memakai pencarian nama Kelompok Aset
      // yang luas: risikonya adalah barang non-Kantin ikut berubah. Relasi
      // Produk -> Master Aset hanya diterapkan oleh endpoint server di atas,
      // yang menghitung scope dari transaksi Penjualan/HPP/Kulakan belum posting.
    }

    try {
      final audit = await call('pemetaan_akun_kantin_audit', {
        'tokoId': 1,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
      });
      // ignore: avoid_print
      print('KANTIN_ACCOUNT_SERVER_AUDIT=${jsonEncode(audit)}');
    } catch (e) {
      // ignore: avoid_print
      print('KANTIN_ACCOUNT_SERVER_AUDIT_UNAVAILABLE=$e');
      if (e is ApiException) {
        // ignore: avoid_print
        print('KANTIN_ACCOUNT_SERVER_AUDIT_TECHNICAL=${e.teknis}');
      }
    }

    Future<Map<String, dynamic>> preview(String kind) async {
      if (kind == 'kulakan') {
        return call('posting_kulakan_draft', {
          'mulai': '2026-09-01',
          'sampai': '2026-09-30',
        });
      }
      return call('laporan_keuangan_pendukung', {
        'jenis': kind,
        'mulai': '2026-09-01',
        'sampai': '2026-09-30',
        'posting': false,
      });
    }

    for (final kind in ['penjualan', 'hpp', 'kulakan']) {
      Map<String, dynamic> before;
      try {
        before = await preview(kind);
      } catch (e) {
        // ignore: avoid_print
        print('KANTIN_${kind.toUpperCase()}_PREVIEW_ERROR=$e');
        if (e is ApiException) {
          // ignore: avoid_print
          print('KANTIN_${kind.toUpperCase()}_PREVIEW_TECHNICAL=${e.teknis}');
        }
        rethrow;
      }
      final data = Map<String, dynamic>.from(
        (before['data'] as Map?) ?? before,
      );
      final rows = ((data['rincian'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final ready = rows.where((e) => e['siap'] == true).toList();
      final blocked = rows.where((e) => e['siap'] != true).toList();
      // ignore: avoid_print
      print('KANTIN_${kind.toUpperCase()}_AUDIT=${jsonEncode({
            'jumlah': rows.length,
            'siap': ready.length,
            'tertahan': blocked.length,
            'total': data['total'] ?? data['totalSiap'],
            'contohSiap': ready.take(2).toList(),
            'contohTertahan': blocked.take(3).toList(),
          })}');
      if (post && ready.isNotEmpty) {
        final ids = ready.map((e) => e['id']).where((e) => e != null).toList();
        final result = kind == 'kulakan'
            ? await call('posting_kulakan_terapkan', {
                'mulai': '2026-09-01',
                'sampai': '2026-09-30',
                'posting_ids': ids,
              })
            : await call('laporan_keuangan_pendukung', {
                'jenis': kind,
                'mulai': '2026-09-01',
                'sampai': '2026-09-30',
                'posting': true,
                'posting_ids': ids,
              });
        // ignore: avoid_print
        print('KANTIN_${kind.toUpperCase()}_POST=${jsonEncode(result)}');
      }
    }
  });
}
