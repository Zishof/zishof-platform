import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

File _server(String path) => File(
      'C:/opt/AIS/ais/src/main/src/$path',
    );

void main() {
  test('kontrak status posting eksplisit dan batas riwayat aman', () {
    final source = _server(
      'ais/action/servlet/api/PostingStatusUtil.java',
    );
    if (!source.existsSync()) return;
    final isi = _rapat(source.readAsStringSync());

    expect(isi, contains('BELUM_DIPOSTING_SIAP'));
    expect(isi, contains('BELUM_DIPOSTING_TERTAHAN'));
    expect(isi, contains('SUDAH_DIPOSTING'));
    expect(isi, contains('baris.put("sudahDiposting",false)'));
    expect(isi, contains('baris.put("sudahDiposting",true)'));
    expect(isi, contains('if(nilai<100){return100;}'));
    expect(isi, contains('Math.min(nilai,10000)'));
  });

  test('penjualan dan HPP mengirim draf serta riwayat terposting', () {
    for (final path in [
      'ais/action/master/koperasi/PostingPenjualanKantinAction.java',
      'ais/action/master/koperasi/PostingHppKantinAction.java',
    ]) {
      final source = _server(path);
      if (!source.existsSync()) continue;
      final isi = _rapat(source.readAsStringSync());
      expect(isi, contains('hasil.put("rincian",newJSONArray(rincianDraft))'),
          reason: path);
      expect(isi, contains('hasil.put("rincianSudahDiposting",sudah)'),
          reason: path);
      expect(isi, contains('hasil.put("jumlahBelumDiposting",'), reason: path);
      expect(isi, contains('hasil.put("jumlahSudahDiposting",sudah.length())'),
          reason: path);
      expect(isi, contains('PostingStatusUtil.tandaiBelum('), reason: path);
    }
  });

  test('posting lanjutan memakai kontrak status yang sama', () {
    final source = _server(
      'ais/action/servlet/api/PostingKantinLanjutanHelper.java',
    );
    if (!source.existsSync()) return;
    final isi = _rapat(source.readAsStringSync());

    expect(isi, contains('PostingStatusUtil.tandaiBelum(j,d.siap())'));
    expect(isi, contains('hasil.put("rincianSudahDiposting",sudah)'));
    expect(isi, contains('"kulakan".equals(jenis)'));
    expect(isi, contains('"bayar_hutang".equals(jenis)'));
    expect(isi, contains('"terima_piutang".equals(jenis)'));
  });

  test('adapter POS meneruskan batas riwayat ke penjualan dan HPP', () {
    final source = _server('ais/action/servlet/PosApi.java');
    if (!source.existsSync()) return;
    final isi = _rapat(source.readAsStringSync());

    expect(isi, contains('PostingStatusUtil.batasRiwayat(payload)'));
    expect(
      RegExp(r'prosesApi\([^;]+batasRiwayat\)').allMatches(isi).length,
      greaterThanOrEqualTo(4),
    );
  });
}
