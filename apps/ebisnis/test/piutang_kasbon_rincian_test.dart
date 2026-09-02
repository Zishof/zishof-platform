import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '').toLowerCase();

void main() {
  final layar =
      File('lib/screens/laporan_detail_screen.dart').readAsStringSync();
  final padat = _rapat(layar);

  test('saldo piutang mengirim filter Kasbon dan kode pelanggan yang tepat',
      () {
    expect(padat, contains("idl aporan=='ar_saldo'".replaceAll(' ', '')));
    expect(padat, contains("hasil['hanyapiutang']=true"));
    expect(padat, contains("hasil['kodepelanggan']=nilai"));
    expect(padat, isNot(contains("hasil['hanyabelumlunas']=true")));
  });

  test('popup piutang menampilkan jenis, nilai faktur, dan rincian produk', () {
    expect(padat, contains("text('metodepembayaran')"));
    expect(padat, contains("text('jenispiutang')"));
    expect(padat, contains("text('piutangfaktur')"));
    expect(padat, contains("text('produk')"));
    expect(padat, contains("snap.data?['totalpiutang']"));
  });

  test('kontrak backend menolak Voucher dan QRIS dari sumber piutang', () {
    final backend = File(r'C:\opt\AIS\ais\src\main\src\ais\action\master'
        r'\koperasi\helper\LaporanRincianTransaksiUtil.java');
    if (!backend.existsSync()) return;
    final sumber = _rapat(backend.readAsStringSync());
    expect(sumber, contains('masuk_sebagai_hutang,false)=true'));
    expect(sumber, contains("like'%kasbon%'"));
    expect(sumber, contains('daftarmetodepembayarannota'));
    expect(sumber, contains('totalpiutang'));
  });
}
