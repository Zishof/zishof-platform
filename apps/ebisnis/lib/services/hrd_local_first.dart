import 'dart:convert';

import '../app_variant.dart';
import '../api_client.dart';
import '../sesi.dart';
import 'master_offline.dart';

/// Gerbang baca lokal-dulu untuk seluruh data HRD.
///
/// Kunci cache selalu memuat varian, tenant, pengguna, aksi, dan parameter.
/// Snapshot milik tenant atau hak akses lain karena itu tidak dapat dipakai
/// sebagai fallback pada sesi yang sedang aktif.
class HrdLocalFirst {
  HrdLocalFirst._();

  static String kunci(String aksi, Map<String, dynamic> body) {
    final sesi = Sesi.instance;
    final tenantId = sesi.tenantId;
    final userId = sesi.userId.trim().toLowerCase();
    if (tenantId == null || tenantId <= 0 || userId.isEmpty) {
      throw StateError(
          'Konteks tenant dan pengguna wajib aktif sebelum membaca data HRD.');
    }
    final urut = <String, dynamic>{};
    final keys = body.keys.toList()..sort();
    for (final key in keys) {
      urut[key] = body[key];
    }
    final parameter =
        base64Url.encode(utf8.encode(jsonEncode(urut))).replaceAll('=', '');
    return 'hrd:${AppVariant.storageNamespace}:'
        'tenant-$tenantId:'
        'user-$userId:'
        '$aksi:$parameter';
  }

  static Future<void> baca(
    String aksi,
    Map<String, dynamic> body, {
    required void Function(Map<String, dynamic> hasil) onData,
  }) async {
    // Token dan tenant dipulihkan sebelum layar utama tampil. Pada instalasi
    // lama userId belum pernah disimpan, atau layar dapat dibuka ketika
    // konfigurasi awal masih diproses. Pulihkan identitas dari server sekali
    // sebelum membentuk kunci cache; tetap fail-closed bila konteks sah tidak
    // dapat diperoleh (misalnya instalasi pertama sedang luring).
    final sesi = Sesi.instance;
    if (sesi.tenantId != null &&
        sesi.tenantId! > 0 &&
        sesi.userId.trim().isEmpty &&
        ApiClient.instance.sudahLogin) {
      final konfig = await ApiClient.instance.aksi('konfigurasi');
      sesi.terapkanKonfig(konfig);
      await ApiClient.instance.simpanUserIdAktif(sesi.userId);
    }
    return MasterOffline.objekCacheDulu(
      aksi,
      body,
      kunci(aksi, body),
      onData: onData,
    );
  }
}
