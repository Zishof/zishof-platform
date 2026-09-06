import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _bacaBackend(String nama) => File(
      '../../../AIS/ais/src/main/src/ais/action/master/koperasi/helper/$nama',
    ).readAsStringSync();

String _rapat(String nilai) => nilai.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('empat sheet sumber tersedia sebagai empat laporan Omzet', () {
    final katalog = _bacaBackend('LaporanKatalogData.java');

    expect(katalog, contains('new Kat("Omzet")'));
    expect(katalog, contains('"omzet_transaksi"'));
    expect(katalog, contains('"omzet_tunai_produk"'));
    expect(katalog, contains('"omzet_saldo_produk"'));
    expect(katalog, contains('"omzet_rekapan"'));
  });

  test('kolom laporan mengikuti Worksheet, TUNAI, SALDO, dan REKAPAN', () {
    final laporan = _bacaBackend('LaporanKantinUtil.java');

    for (final label in <String>[
      'No. Transaksi',
      'Tipe Pengguna',
      'Jenis Transaksi',
      'Nomor Pembayaran',
      'Tunggakan',
      'Autodebet',
      'Penerima Transfer',
      'Modal Rata-rata',
      'Harga Rata-rata',
      'Terjual',
      'Omzet',
      'Profit',
      'Tunai / Non-Saldo',
      'Total Omzet',
    ]) {
      expect(laporan, contains(label), reason: 'kolom $label harus tersedia');
    }
  });

  test('split payment lima slot dialokasikan dengan klasifikasi saldo master',
      () {
    final rincian = _bacaBackend('LaporanRincianTransaksiUtil.java');
    final laporan = _bacaBackend('LaporanKantinUtil.java');

    expect(rincian, contains('memotong_deposit'));
    expect(rincian, contains('.manual,true)=false'));
    for (var slot = 2; slot <= 5; slot++) {
      expect(rincian, contains('nominal_bayar_$slot'));
    }
    expect(laporan, contains('rasioSaldo'));
    expect(laporan, contains('1.0-'));
    expect(laporan, contains('dialokasikan proporsional'));
  });

  test('baris Omzet clickable dan popup membawa dimensi transaksi/toko/metode',
      () {
    final layar =
        File('lib/screens/laporan_detail_screen.dart').readAsStringSync();
    final padat = _rapat(layar);
    final api = File(
      '../../../AIS/ais/src/main/src/ais/action/servlet/PosApi.java',
    ).readAsStringSync();
    final rincian = _bacaBackend('LaporanRincianTransaksiUtil.java');

    expect(padat, contains(_rapat("widget.idLaporan.startsWith('omzet_')")));
    expect(layar, contains("hasil['idTransaksi'] = nilai"));
    expect(layar, contains("hasil['kelompokPembayaran'] = 'SALDO'"));
    expect(layar, contains("hasil['kelompokPembayaran'] = 'NON_SALDO'"));
    expect(layar, contains("'tokoId': payloadFilter['tokoId']"));
    expect(api, contains('payload.optString("idTransaksi", "")'));
    expect(api, contains('payload.optString("kelompokPembayaran", "")'));
    expect(rincian, contains('CAST(pak.id AS text)=?'));
    expect(rincian,
        contains("COALESCE(pr.nama,'') ILIKE ? OR COALESCE(NULLIF(TRIM(a.nama),''),'') ILIKE ?"),
        reason: 'popup produk harus cocok dengan nama master maupun label transaksi');
  });

  test('popup lintas toko supervisor tetap dibatasi tenant dan tidak ditolak',
      () {
    final api = File(
      '../../../AIS/ais/src/main/src/ais/action/servlet/PosApi.java',
    ).readAsStringSync();
    final mulai = api.indexOf('private void prosesLaporanRincianTransaksi');
    final selesai = api.indexOf('\n\tprivate ', mulai + 1);
    final blok = api.substring(mulai, selesai);

    expect(blok, contains('!bolehSupervisorAtauAdmin(tbmuser)'));
    expect(blok, contains('!bolehLihatSemuaToko(tbmuser)'));
    expect(blok, contains('dim.pendaftarId = pendaftarIdPengguna(tbmuser)'));
    expect(blok, isNot(contains('if (tokoId == null) {')),
        reason: 'guard tanpa pengecualian memblokir popup akun admin Nahl');
  });

  test('setiap laporan memakai jalur ekspor XLSX dan PDF generik', () {
    final layar =
        File('lib/screens/laporan_detail_screen.dart').readAsStringSync();

    expect(layar, contains('final bytes = _bangunXlsx(kolom, baris)'));
    expect(layar, contains(".aksi('laporan_pdf'"));
    expect(layar, contains('FilePicker.platform.saveFile'));
  });

  test('dua mirror backend tetap identik', () {
    for (final nama in <String>[
      'LaporanKatalogData.java',
      'LaporanKantinUtil.java',
      'LaporanRincianTransaksiUtil.java',
    ]) {
      final utama = File(
        '../../../AIS/ais/src/main/src/ais/action/master/koperasi/helper/$nama',
      ).readAsStringSync();
      final mirror = File(
        '../../../AIS/ais/src/main/java/ais/action/master/koperasi/helper/$nama',
      ).readAsStringSync();
      expect(mirror, utama, reason: '$nama harus identik pada dua source tree');
    }
    final posUtama = File(
      '../../../AIS/ais/src/main/src/ais/action/servlet/PosApi.java',
    ).readAsStringSync();
    final posMirror = File(
      '../../../AIS/ais/src/main/java/ais/action/servlet/PosApi.java',
    ).readAsStringSync();
    expect(posMirror, posUtama,
        reason: 'PosApi.java harus identik pada dua source tree');
  });
}
