import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/kulakan_local_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache Kulakan dipisahkan per tenant dan toko', () {
    expect(kunciCacheKulakan(tenantId: 7, tokoId: 10),
        isNot(kunciCacheKulakan(tenantId: 7, tokoId: 11)));
    expect(kunciCacheKulakan(tenantId: 7, tokoId: 10),
        isNot(kunciCacheKulakan(tenantId: 8, tokoId: 10)));
    expect(kunciCacheKulakan(tenantId: 7, tokoId: 10),
        kunciCacheKulakan(tenantId: 7, tokoId: 10));
  });

  test('daftar, detail, dan batal Kulakan membawa toko aktif', () {
    for (final aksi in const [
      'kulakan_faktur_list',
      'kulakan_faktur_detail',
      'kulakan_faktur_batal',
      'kulakan_faktur_simpan',
    ]) {
      expect(ApiClient.aksiMemakaiTokoId(aksi), isTrue, reason: aksi);
    }
  });

  test('layar menyediakan unduh rekap seluruh faktur, bukan halaman aktif', () {
    final source = File('lib/screens/kulakan_screen.dart').readAsStringSync();

    expect(source, contains("label: const Text('Unduh Rekap Excel')"));
    expect(source, contains("label: const Text('Unduh Rekap PDF')"));
    expect(source, contains("'page_size': 100"));
    expect(source, contains('semua.length < total'));
  });
}
