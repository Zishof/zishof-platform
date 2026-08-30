import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap varian menginisialisasi locale Indonesia sebelum UI', () {
    final source = File('lib/bootstrap.dart').readAsStringSync();
    expect(source, contains("initializeDateFormatting('id_ID', null)"));
    expect(source.indexOf("initializeDateFormatting('id_ID', null)"),
        lessThan(source.indexOf('runApp(const EBisnisApp())')));
  });

  test('tab SO Harian memuat daftar terjual, checklist, ekspor, dan cache', () {
    final source =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();

    expect(source, contains("Tab(text: 'SO Harian')"));
    expect(source, contains('class _TabSoHarian'));
    expect(source, contains("'so_harian'"));
    expect(source, contains("'so_harian_download_excel'"));
    expect(source, contains("'so_harian_upload_excel_preview'"));
    expect(source, contains("'so_harian_upload_excel'"));
    expect(source, contains('MasterOffline.objekDenganCache('));
    expect(source, contains('PenandaDataTersimpan(tampil: _dariCache)'));
    expect(source, contains('SharedPreferences.getInstance()'));
    expect(source, contains("label: const Text('Unduh Excel')"));
    expect(source, contains("label: const Text('Unggah Excel')"));
    expect(source, contains('Pratinjau Unggah SO Harian'));
    expect(source, contains('Penyimpanan bersifat satu batch'));
    expect(source, contains("label: const Text('Cetak PDF')"));
    expect(source, contains("AppTableColumn('Terjual'"));
    expect(source, contains("AppTableColumn('Sisa Stok Saat Ini'"));
    expect(source, contains("'Sisa Stok Saat Ini',"));
    expect(
      source,
      contains('transaksi yang masih pending belum masuk laporan server'),
    );
  });

  test('API client menambahkan toko aktif untuk kedua aksi SO Harian', () {
    final source = File('lib/api_client.dart').readAsStringSync();
    expect(source, contains("'so_harian'"));
    expect(source, contains("'so_harian_download_excel'"));
    expect(source, contains("'so_harian_upload_excel_preview'"));
    expect(source, contains("'so_harian_upload_excel'"));
    expect(source, contains("'so_harian_ekspor_excel'"));
  });
}
