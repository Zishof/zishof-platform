import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CoreDb.instance singleton stabil', () {
    expect(CoreDb.instance, same(CoreDb.instance));
  });

  test(
      'UAT transaksi dipulihkan, disimpan lokal, dan tetap diarsipkan sesudah sinkron',
      () async {
    CoreDb.configureStorage('uat_ebisnis');
    final root = await Directory.systemTemp.createTemp('ebisnis-core-db-uat-');
    final support = Directory('${root.path}${Platform.pathSeparator}support');
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    await support.create(recursive: true);
    final backupDirectory = Directory(
        '${documents.path}${Platform.pathSeparator}eBisnis${Platform.pathSeparator}uat_ebisnis${Platform.pathSeparator}Backup');
    await backupDirectory.create(recursive: true);

    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });

    final backup = File(
        '${backupDirectory.path}${Platform.pathSeparator}transaksi-pos-uat_ebisnis-backup.jsonl');
    final payloadPulih = jsonEncode(<String, Object?>{
      'kodeUnik': 'UAT-PULIH-001',
      'kasir': 'uat-kasir',
      'idToko': 1,
      'total': 12500,
      'waktu': '17-08-2026 20:00:00',
      'transaksi': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'nama': 'Produk UAT',
          'jumlah': 1,
          'harga': 12500
        }
      ],
    });
    await backup.writeAsString('${jsonEncode(<String, Object?>{
          'versi': 1,
          'kode_unik': 'UAT-PULIH-001',
          'payload_json': payloadPulih,
          'status': 'PENDING',
          'dibuat_pada': '2026-08-17T20:00:00',
          'akun_kunci': 'uat-kasir',
          'toko_id': 1,
          'id_perangkat': 'uat-device',
          'percobaan': 0,
        })}\n');

    final pulih = await CoreDb.instance
        .transaksiArsipLokal(akunKunci: 'uat-kasir', tokoId: 1);
    expect(pulih.any((row) => row['kode_unik'] == 'UAT-PULIH-001'), isTrue,
        reason: 'backup di luar DB harus membangun ulang arsip SQLite');

    final payloadBaru = jsonEncode(<String, Object?>{
      'kodeUnik': 'UAT-BARU-002',
      'kasir': 'uat-kasir',
      'idToko': 1,
      'total': 25000,
      'waktu': '17-08-2026 20:01:00',
      'transaksi': <Map<String, Object?>>[
        <String, Object?>{
          'id': 2,
          'nama': 'Produk Baru',
          'jumlah': 2,
          'harga': 12500
        }
      ],
    });
    await CoreDb.instance.simpanTransaksiPending(
      'UAT-BARU-002',
      payloadBaru,
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    await CoreDb.instance.tandaiTransaksiSinkron('UAT-BARU-002');

    final arsip = await CoreDb.instance
        .transaksiArsipLokal(akunKunci: 'uat-kasir', tokoId: 1);
    final baru = arsip.firstWhere((row) => row['kode_unik'] == 'UAT-BARU-002');
    expect(baru['status'], 'SYNCED');
    expect(baru['disinkronkan_pada'], isNotNull);
    expect(await backup.readAsLines(), hasLength(greaterThanOrEqualTo(3)),
        reason:
            'backup append-only harus menyimpan snapshot pending dan synced');

    await CoreDb.instance.simpanTransaksiPending(
      'UAT-DEDUPE-003',
      jsonEncode(<String, Object?>{
        'kodeUnik': 'UAT-DEDUPE-003',
        'total': 30000,
        'sumber': 'lokal-belum-terkirim'
      }),
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    final ditimpaPending = await CoreDb.instance.simpanTransaksiDariServer(
      'UAT-DEDUPE-003',
      jsonEncode(<String, Object?>{
        'kodeUnik': 'UAT-DEDUPE-003',
        'total': 1,
        'sumber': 'server'
      }),
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    expect(ditimpaPending, isFalse,
        reason: 'payload pending lokal tidak boleh ditimpa snapshot server');
    final pendingTerjaga =
        await CoreDb.instance.transaksiLokalDenganKode('UAT-DEDUPE-003');
    expect(pendingTerjaga?['status'], 'PENDING');
    expect(
        '${pendingTerjaga?['payload_json']}', contains('lokal-belum-terkirim'));

    await CoreDb.instance.tandaiTransaksiSinkron('UAT-DEDUPE-003');
    final diperbarui = await CoreDb.instance.simpanTransaksiDariServer(
      'UAT-DEDUPE-003',
      jsonEncode(<String, Object?>{
        'kodeUnik': 'UAT-DEDUPE-003',
        'total': 30000,
        'sumber': 'server-terverifikasi'
      }),
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    expect(diperbarui, isTrue);
    final satuKode = (await CoreDb.instance.transaksiArsipLokal(tokoId: 1))
        .where((row) => row['kode_unik'] == 'UAT-DEDUPE-003')
        .toList();
    expect(satuKode, hasLength(1),
        reason: 'kode_unik harus mencegah transaksi ganda');
    expect(
        '${satuKode.single['payload_json']}', contains('server-terverifikasi'));

    await CoreDb.instance.simpanTransaksiPending(
      'UAT-RETRY-004',
      jsonEncode(<String, Object?>{
        'kodeUnik': 'UAT-RETRY-004',
        'kasir': 'uat-kasir',
        'idToko': 1,
        'total': 40000,
      }),
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    await CoreDb.instance
        .tandaiTransaksiGagal('UAT-RETRY-004', 'gangguan jaringan UAT');
    final belumSepuluhMenit =
        await CoreDb.instance.transaksiPendingBelumSinkron(
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
    );
    expect(
        belumSepuluhMenit.where((row) => row['kode_unik'] == 'UAT-RETRY-004'),
        isEmpty,
        reason: 'transaksi gagal tidak boleh langsung dipukul ulang');
    final tanpaJedaUntukUat =
        await CoreDb.instance.transaksiPendingBelumSinkron(
      akunKunci: 'uat-kasir',
      tokoId: 1,
      idPerangkat: 'uat-device',
      jedaRetry: Duration.zero,
    );
    expect(tanpaJedaUntukUat.any((row) => row['kode_unik'] == 'UAT-RETRY-004'),
        isTrue,
        reason: 'baris tetap pending dan layak dikirim setelah jeda berakhir');

    // UAT katalog besar: layar Kasir tidak boleh membaca semua cache saat
    // dibuka. Query awal dan hasil pencarian harus menghormati batas baris.
    final produkUat = <Map<String, Object?>>[];
    for (var i = 1; i <= 150; i++) {
      produkUat.add(<String, Object?>{
        'id': i,
        'kode': 'UAT-PRODUK-$i',
        'barcode': '899000${i.toString().padLeft(6, '0')}',
        'nama': i == 149 ? 'Produk Khusus Lazy' : 'Produk UAT $i',
        'harga_jual': 1000 + i,
        'stok': i,
        'aktif': 1,
        'jenis_item': 'JUAL',
      });
    }
    await CoreDb.instance.upsertProdukCache(produkUat);
    final halamanAwal = await CoreDb.instance.produkCache(limit: 80);
    expect(halamanAwal, hasLength(80),
        reason: 'pembukaan Kasir hanya membaca halaman kecil cache lokal');
    final hasilLazy =
        await CoreDb.instance.produkCache(keyword: 'khusus lazy', limit: 100);
    expect(hasilLazy, hasLength(1));
    expect(hasilLazy.single['kode'], 'UAT-PRODUK-149');

    // UAT kebijakan member: aturan PIN dan limit tipe harus selamat dalam
    // snapshot lokal. Tanpa tiga kolom limit ini, kasir offline akan salah
    // menganggap transaksi bebas limit lalu baru mengetahuinya di background.
    await CoreDb.instance.upsertAnggotaCache(<Map<String, Object?>>[
      <String, Object?>{
        'id': 7001,
        'kode': 'MEM-UAT-7001',
        'nama': 'Member PIN dan Limit',
        'kode_identitas': 'UAT-7001',
        'wajib_pin': 1,
        'maksimal_transaksi_harian': 50000.0,
        'maksimal_transaksi_mingguan': 200000.0,
        'maksimal_transaksi_bulanan': 600000.0,
      }
    ]);
    final memberLimit = await CoreDb.instance.cariAnggotaCache('UAT-7001');
    expect(memberLimit, hasLength(1));
    expect(memberLimit.single['wajib_pin'], 1);
    expect(memberLimit.single['maksimal_transaksi_harian'], 50000.0);
    expect(memberLimit.single['maksimal_transaksi_mingguan'], 200000.0);
    expect(memberLimit.single['maksimal_transaksi_bulanan'], 600000.0);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // Handle SQLite FFI masih hidup sampai proses test berakhir di Windows.
    }
  });
}
