import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filter metode penjualan kasir diteruskan ke grid dan ekspor', () {
    final servlet =
        File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\PosApi.java');
    if (!servlet.existsSync()) return;

    final source = servlet.readAsStringSync();
    final awal = source.indexOf('private void prosesLaporanPenjualanKasirList');
    final akhir =
        source.indexOf('private void prosesLaporanPenjualanKasirDetail', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));

    final method = source.substring(awal, akhir);
    expect(method, contains('aman.put("metodeExact", metodeDipilih)'));
    expect(method.indexOf('aman.put("metodeExact", metodeDipilih)'),
        lessThan(method.indexOf('daftarOrderDenganSesi(session')),
        reason: 'filter wajib masuk sebelum query grid dijalankan');

    final query = source.substring(
        source.indexOf('private JSONObject daftarOrderDenganSesi'),
        source.indexOf('private static String lpad',
            source.indexOf('private JSONObject daftarOrderDenganSesi')));
    expect(query, contains("LOWER(TRIM(COALESCE(a.carabayar,''))) = LOWER(?)"));
    expect(query, contains("LOWER(TRIM(COALESCE(cbx.nama,''))) = LOWER(?)"));
    expect(query, isNot(contains('paramsTrx.add("%" + metodeExact + "%")')),
        reason:
            'Tunai tidak boleh mencocokkan nama metode lain secara substring');
  });

  test('rincian produk membuka rekap kumulatif sebagai mode awal', () {
    final source =
        File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync();
    expect(source, contains('bool _modeRekap = true;'));
    expect(source, contains('_muatRekap();'));

    final servlet =
        File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\PosApi.java');
    if (!servlet.existsSync()) return;
    final backend = servlet.readAsStringSync();
    expect(backend, contains('b.put("produkId"'));
    expect(backend, contains('b.put("produkKodeRekap"'));
    expect(backend, contains('b.put("produkNamaRekap"'));
  });

  test('rincian produk meneruskan filter kasir dan metode bayar', () {
    final source =
        File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync();
    final awal = source.indexOf('class _TabRincianProdukState');
    expect(awal, greaterThanOrEqualTo(0));
    final akhir = source.indexOf('Widget build(BuildContext context)', awal);
    expect(akhir, greaterThan(awal));

    final state = source.substring(awal, akhir);
    expect(
        state, contains("ApiClient.instance.aksi('laporan_metode_bayar_opsi'"));
    expect(state,
        contains("if (_kasir.trim().isNotEmpty) 'kasir': _kasir.trim()"));
    expect(state,
        contains("if (_metode.trim().isNotEmpty) 'metode': _metode.trim()"));
    expect(state, contains("hasil['bolehFilterKasir'] != false"));
    expect(state, contains("hasil['daftarKasir']"));

    final ui = source.substring(
        akhir,
        source.indexOf(
            '_AnalitikLaporanFooter(statistik: widget.statistik)', akhir));
    expect(ui, contains("labelText: 'Kasir'"));
    expect(ui, contains("labelText: 'Metode Bayar'"));
    expect(ui, contains("Text('Semua kasir')"));
    expect(ui, contains("Text('Semua metode')"));
  });
}
