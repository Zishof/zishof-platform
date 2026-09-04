import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('laporan pemasok dirinci per produk dan UOM oleh backend bersama', () {
    final kandidat = [
      File(
        '../../../AIS/ais/src/main/src/ais/action/master/koperasi/helper/LaporanKantinUtil.java',
      ),
      File(
        r'C:\opt\AIS\ais\src\main\src\ais\action\master\koperasi\helper\LaporanKantinUtil.java',
      ),
      File(
        '../../../AIS-apotik-v13424/ais/src/main/src/ais/action/master/koperasi/helper/LaporanKantinUtil.java',
      ),
    ];
    final sumber = kandidat.firstWhere(
      (file) => file.existsSync(),
      orElse: () => kandidat.first,
    );
    expect(
      sumber.existsSync(),
      isTrue,
      reason:
          'Checkout AIS tidak ditemukan pada salah satu lokasi yang didukung.',
    );
    final source = sumber.readAsStringSync();

    final mulai = source.indexOf('"pnj_per_pemasok".equals(r)');
    final selesai = source.indexOf('"pnj_uang_muka".equals(r)', mulai);
    expect(mulai, greaterThanOrEqualTo(0));
    expect(selesai, greaterThan(mulai));
    final blok = source.substring(mulai, selesai);

    expect(blok, contains('grupIdx = 0'));
    expect(blok, contains('KODE_PRODUK_ITEM'));
    expect(blok, contains('NAMA_PRODUK_ITEM'));
    expect(blok, contains('NAMA_SATUAN_TRANSAKSI'));
    expect(blok, contains('QTY_UOM_ITEM'));
    expect(blok, contains('Qty UOM'));
    expect(blok, contains('Qty Dasar'));
    expect(blok, contains('Total Penjualan'));
  });

  test('endpoint laporan generik melayani layar, Excel, dan PDF', () {
    final source =
        File('lib/screens/laporan_detail_screen.dart').readAsStringSync();

    expect(source, contains(".aksi('laporan_jalankan'"));
    expect(source, contains(".aksi('laporan_pdf'"));
    expect(source, contains('final bytes = _bangunXlsx(kolom, baris)'));
    expect(source, contains('FilePicker.platform.saveFile'));
  });
}
