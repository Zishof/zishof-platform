import 'package:ebisnis/screens/riwayat_penjualan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot riwayat tidak tertukar antar tanggal, akun, toko dan halaman',
      () {
    final filter = <String, dynamic>{
      'tglMulai': '2026-09-21',
      'tglSampai': '2026-09-21',
      'page': 1
    };
    final key = kunciCacheRiwayatPenjualan('uji', 1, filter);
    expect(
        kunciCacheRiwayatPenjualan('uji', 1,
            {'page': 1, 'tglSampai': '2026-09-21', 'tglMulai': '2026-09-21'}),
        key);
    expect(kunciCacheRiwayatPenjualan('lain', 1, filter), isNot(key));
    expect(kunciCacheRiwayatPenjualan('uji', 2, filter), isNot(key));
    expect(kunciCacheRiwayatPenjualan('uji', 1, {...filter, 'page': 2}),
        isNot(key));
    expect(
        kunciCacheRiwayatPenjualan(
            'uji', 1, {...filter, 'tglMulai': '2026-09-20'}),
        isNot(key));
    expect(kunciCacheRiwayatPenjualan('uji', 1, {...filter, 'keyword': 'uji'}),
        isNot(key));
  });
  test('status lokal selesai tanpa ID server tidak mengaku tersinkron', () {
    expect(labelStatusArsipTransaksi({'statusSinkronLokal': 'SYNCED'}),
        contains('belum dicocokkan server'));
    expect(labelStatusArsipTransaksi({'statusSinkronLokal': 'PENDING'}),
        contains('menunggu sinkron'));
    expect(
        labelStatusArsipTransaksi(
            {'statusSinkronLokal': 'SYNCED', 'idTransaksi': 1}),
        'Tercatat pada data server');
  });
}
