import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';

/// Penjaga pengikatan perangkat ke satu tenant.
///
/// Satu perangkat melayani satu tenant. Yang diuji di sini adalah keadaan yang
/// jarang tetapi mahal: perangkat yang **dialihkan** ke tenant lain — pegawai
/// pindah cabang, perangkat dipakai ulang, atau salah login.
///
/// Berkas uji terpisah = proses terpisah, jadi namespace `CoreDb` boleh diatur
/// sekali di sini tanpa bentrok dengan berkas uji lain.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pengikatan menolak percampuran tenant, dan hanya melepas saat antrean kosong',
      () async {
    CoreDb.configureStorage('uji_pengikatan');
    final root = await Directory.systemTemp.createTemp('ebisnis-pengikatan-');
    final support = Directory('${root.path}${Platform.pathSeparator}support');
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    await support.create(recursive: true);
    await documents.create(recursive: true);

    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      if (call.method == 'getApplicationDocumentsDirectory') {
        return documents.path;
      }
      return null;
    });

    final db = CoreDb.instance;

    // -- Pemasangan baru: belum terikat, dan antreannya kosong.
    expect(await db.periksaPengikatan(7), StatusPengikatan.belumTerikat);
    expect(await db.hitungAntreanTertunda(), 0);
    expect(await db.pengikatanSekarang(), isNull);

    // -- Diikat ke tenant 7.
    await db.ikatTenant(tenantId: 7, tenantKode: 'TEN-7', serverSidik: 's1');
    expect(await db.periksaPengikatan(7), StatusPengikatan.cocok);

    final terikat = await db.pengikatanSekarang();
    expect(terikat, isNotNull);
    expect(terikat!['tenant_id'], 7);
    expect(terikat['tenant_kode'], 'TEN-7');
    expect(terikat['terikat_pada'], isNotNull);

    // -- Tenant lain terdeteksi BEDA, bukan diam-diam diterima.
    expect(await db.periksaPengikatan(8), StatusPengikatan.beda);

    // -- Mengikat ulang menimpa, tetap satu baris (CHECK id = 1).
    await db.ikatTenant(tenantId: 8, tenantKode: 'TEN-8');
    expect(await db.periksaPengikatan(8), StatusPengikatan.cocok);
    expect(await db.periksaPengikatan(7), StatusPengikatan.beda);
    final database = await db.db;
    final baris = await database.query('pengikatan_tenant');
    expect(baris.length, 1, reason: 'pengikatan harus tepat satu baris');

    // -- Antrean tertunda terhitung dari KETIGA sumbernya.
    await db.outboxMasterTambah('produk_simpan', 'produk:1', '{}');
    expect(await db.hitungAntreanTertunda(), 1,
        reason: 'outbox_master harus ikut terhitung');
    await db.outboxIsTambah('si_expense_create', 'UNIK-1', '{}');
    expect(await db.hitungAntreanTertunda(), 2,
        reason: 'outbox_is harus ikut terhitung');

    // -- Melepas dan mengarsipkan: berkasnya DIPINDAH, bukan dihapus (§15.4).
    final sebelum = File('${support.path}${Platform.pathSeparator}'
        'ebisnis_uji_pengikatan.db');
    expect(sebelum.existsSync(), isTrue);

    final arsip = await db.lepaskanDanArsipkan();
    expect(arsip, isNotNull);
    expect(File(arsip!).existsSync(), isTrue,
        reason: 'berkas lama wajib tetap ada, hanya berganti nama');
    expect(sebelum.existsSync(), isFalse,
        reason: 'berkas aktif harus sudah tidak ada sesudah dilepas');

    // -- Pembukaan berikutnya memulai dari nol: tanpa pengikatan, tanpa antrean.
    expect(await db.periksaPengikatan(8), StatusPengikatan.belumTerikat);
    expect(await db.hitungAntreanTertunda(), 0,
        reason: 'antrean tenant lama tidak boleh ikut ke basis data baru');
  });
}
