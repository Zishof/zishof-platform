import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';

String _padat(String nilai) =>
    nilai.replaceAll(RegExp(r'\s+'), '').toLowerCase();

void main() {
  final layar = File('lib/screens/anggota/tab_mutasi_hutang.dart');
  final anggota = File('lib/screens/anggota_screen.dart');

  test('tab memakai istilah Mutasi Piutang dan menyediakan detail barang', () {
    final sumber = _padat(layar.readAsStringSync());
    final induk = anggota.readAsStringSync();

    expect(induk, contains("Tab(text: 'Mutasi Piutang')"));
    expect(sumber, contains(_padat("const Text('Lihat Detail')")));
    expect(sumber, contains(_padat("const Text('Barang yang dibeli'")));
    expect(sumber, contains("'mutasi_piutang_detail'"));
    expect(sumber, contains('transaksiid'));
    expect(sumber, contains('slotpiutang'));
  });

  test('entri pelunasan hanya tampil untuk capability khusus', () {
    final sumber = layar.readAsStringSync();

    expect(sumber, contains('Sesi.instance.bolehEntryPelunasanPiutang'));
    expect(sumber, contains("const Text('Entri Pelunasan Piutang')"));
    expect(sumber, isNot(contains('if (Sesi.instance.bolehEntryTopup)')));
  });

  test('detail piutang menerima toko terpilih dari sesi', () {
    final sesi = Sesi.instance;
    sesi.reset();
    sesi.tokoId = 27;

    expect(ApiClient.aksiMemakaiTokoId('mutasi_piutang_detail'), isTrue);
    expect(
      ApiClient.susunPayload('mutasi_piutang_detail', {
        'transaksi_id': 100,
        'slot': 2,
      })['toko_id'],
      27,
    );
    sesi.reset();
  });

  test('backend mengunci detail ke toko dan menolak pelunasan berlebih', () {
    final helper = File(
        r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api\KantinHelper.java');
    final servlet =
        File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\PosApi.java');
    if (!helper.existsSync() || !servlet.existsSync()) return;

    final sumber = _padat(helper.readAsStringSync());
    final rute = _padat(servlet.readAsStringSync());
    expect(sumber, contains('mutasipiutangdetail'));
    expect(sumber, contains('whereh.id=?andh.toko=?'));
    expect(sumber, contains('cpk.masuk_sebagai_hutang=true'));
    expect(sumber, contains('p.pembelian_anggota_koperasi=?andp.toko=?'));
    expect(sumber, contains('nominalpelunasanpiutangvalid'));
    expect(sumber, contains('tidakbolehmelebihisisapiutangpelanggan'));
    expect(sumber, contains('forupdate'));
    expect(sumber, contains('bayar.setoleh('));
    expect(sumber, contains('bayar.setolehid('));
    expect(rute, contains('"mutasi_piutang_detail".equals(action)'));
    expect(rute, contains('bolehentrypelunasanpiutang'));
  });
}
