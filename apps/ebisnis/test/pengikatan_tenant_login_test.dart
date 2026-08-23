import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ebisnis/services/pengikatan_tenant.dart';

/// Penjaga keputusan pengikatan pada alur login.
///
/// Yang diuji di sini bukan panggilan jaringannya, melainkan **keputusannya** —
/// bagian yang menentukan seorang kasir boleh masuk atau tidak.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // VerifikatorSandiLokal.hapus() menyentuh SharedPreferences saat pengalihan.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CoreDb.configureStorage('uji_pengikatan_login');
    final root = await Directory.systemTemp.createTemp('ebisnis-ikat-login-');
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
  });

  test('perangkat baru terikat, dan tenant yang sama lewat tanpa halangan',
      () async {
    final pertama = await PengikatanTenant.periksa(tenantId: 11, tenantKode: 'TEN-11');
    expect(pertama.keputusan, KeputusanPengikatan.lanjut);
    expect(pertama.bolehLanjut, isTrue);
    expect(pertama.tenantAktifId, 11,
        reason: 'tenant aktif wajib dikembalikan supaya ApiClient dapat menyetel header');

    final kedua = await PengikatanTenant.periksa(tenantId: 11);
    expect(kedua.keputusan, KeputusanPengikatan.lanjut);
    expect(kedua.tenantAktifId, 11);
  });

  test('tenant berbeda dengan antrean tertunda DITAHAN, bukan dialihkan',
      () async {
    final db = CoreDb.instance;
    await db.outboxMasterTambah('produk_simpan', 'produk:9', '{}');
    expect(await db.hitungAntreanTertunda(), greaterThan(0));

    final hasil = await PengikatanTenant.periksa(tenantId: 22);
    expect(hasil.keputusan, KeputusanPengikatan.tertahanAntrean);
    expect(hasil.bolehLanjut, isFalse,
        reason: 'login WAJIB berhenti -- antrean tenant lama tidak boleh '
            'terkirim memakai token tenant baru');
    expect(hasil.antreanTertunda, greaterThan(0));
    expect(hasil.tenantLamaId, 11);
    expect(PengikatanTenant.pesan(hasil), contains('belum terkirim'));

    // Pengikatan TIDAK boleh berubah selama tertahan.
    final masihLama = await db.pengikatanSekarang();
    expect(masihLama!['tenant_id'], 11,
        reason: 'pengikatan lama harus utuh selama pengalihan ditolak');
  });

  test('tenant berbeda dengan antrean kosong dialihkan dan diarsipkan',
      () async {
    final db = CoreDb.instance;
    // Kosongkan antrean seperti kalau penyiram sudah berhasil mengirimnya.
    final database = await db.db;
    await database.delete('outbox_master');
    expect(await db.hitungAntreanTertunda(), 0);

    final hasil = await PengikatanTenant.periksa(tenantId: 22, tenantKode: 'TEN-22');
    expect(hasil.keputusan, KeputusanPengikatan.dialihkan);
    expect(hasil.bolehLanjut, isTrue);
    expect(hasil.tenantLamaId, 11);
    expect(hasil.tenantAktifId, 22);
    expect(hasil.arsip, isNotNull);
    expect(File(hasil.arsip!).existsSync(), isTrue,
        reason: 'berkas lama diarsipkan, bukan dihapus (§15.4)');

    // Basis data baru: terikat ke 22, tanpa warisan antrean.
    expect(await db.periksaPengikatan(22), StatusPengikatan.cocok);
    expect(await db.hitungAntreanTertunda(), 0);
  });

  test('keadaan yang menahan pengguna punya pesan, yang lolos tidak', () {
    const tertahan = HasilPengikatan(KeputusanPengikatan.tertahanAntrean,
        antreanTertunda: 3);
    expect(PengikatanTenant.pesan(tertahan), contains('3'));
    expect(tertahan.bolehLanjut, isFalse);

    const pilih = HasilPengikatan(KeputusanPengikatan.pilihTenant);
    expect(pilih.bolehLanjut, isFalse,
        reason: 'punya lebih dari satu tenant tanpa memilih tidak boleh lanjut '
            '-- menebak salah satu berarti bekerja pada usaha yang keliru');
    expect(PengikatanTenant.pesan(pilih), isNotEmpty);

    // Pengguna legacy dan admin pusat: LANJUT, tanpa pesan apa pun.
    const tanpa = HasilPengikatan(KeputusanPengikatan.tanpaTenant);
    expect(tanpa.bolehLanjut, isTrue,
        reason: 'seluruh pengguna hari ini tidak punya tenant dan harus tetap '
            'bisa masuk seperti biasa');
    expect(tanpa.tenantAktifId, isNull,
        reason: 'tanpa tenant berarti header X-Tenant-Id tidak dikirim');
    expect(PengikatanTenant.pesan(tanpa), isEmpty);
  });
}
