import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aksi tidak dikenal tidak dianggap stok tidak cukup', () {
    final panduan = panduanResolusiGalat(
      'Aksi tidak dikenal: so_perubahan_stok',
      aktivitas: 'so_perubahan_stok',
    );

    expect(panduan.judul, 'Fitur belum tersedia di server');
    expect(panduan.solusi.join('\n'), contains('versi backend'));
  });

  test('ApiException action tidak dikenal menampilkan judul server lama', () {
    final info = ApiException(
      'Aksi tidak dikenal: so_perubahan_stok',
      aktivitas: 'so_perubahan_stok',
      statusHttp: 200,
    ).info;

    expect(info.judul, 'Fitur belum tersedia di server');
    expect(info.pesan, 'Aksi tidak dikenal: so_perubahan_stok');
  });

  test('action opsional server baru tidak memenuhi Log Error berulang', () {
    final source = File('lib/api_client.dart').readAsStringSync();

    expect(source, contains('_aksiOpsionalServerBaru'));
    expect(source, contains("'so_perubahan_stok'"));
    expect(source, contains("'toko_filter_list'"));
    expect(source, contains("contains('aksi tidak dikenal')"));
  });
}
