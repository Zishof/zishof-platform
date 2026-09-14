import 'dart:io';

import 'package:ebisnis/screens/anggota/tab_topup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filter tipe member dikirim ke server dan reset tetap tanpa filter', () {
    final semua = parameterDaftarTopup(page: 1, pageSize: 15);
    final pegawai = parameterDaftarTopup(
      page: 2,
      pageSize: 15,
      keyword: ' Lale ',
      tipeAnggotaId: 27,
    );

    expect(semua, isNot(contains('tipe_anggota_id')));
    expect(pegawai, {
      'keyword': 'Lale',
      'tipe_anggota_id': 27,
      'page': 2,
      'page_size': 15,
    });
  });

  test('snapshot lokal dipisahkan per tipe member dan kata pencarian', () {
    final semua = kunciCacheDaftarTopup();
    final santri = kunciCacheDaftarTopup(tipeAnggotaId: 11);
    final pegawai = kunciCacheDaftarTopup(tipeAnggotaId: 27);
    final pegawaiLale =
        kunciCacheDaftarTopup(tipeAnggotaId: 27, keyword: 'Lale');

    expect({semua, santri, pegawai, pegawaiLale}, hasLength(4));
    expect(
      kunciCacheDaftarTopup(tipeAnggotaId: 27, keyword: '  LALE  '),
      pegawaiLale,
    );
  });

  test('layar topup menyediakan filter tipe dari master member', () {
    final source =
        File('lib/screens/anggota/tab_topup.dart').readAsStringSync();

    expect(source, contains("'tipe_anggota_list'"));
    expect(source, contains("Key('filter-tipe-member-topup')"));
    expect(source, contains("labelText: 'Tipe Member'"));
    expect(source, contains("Text('Semua tipe member')"));
    expect(source, contains('_ubahTipeMember'));
  });
}
