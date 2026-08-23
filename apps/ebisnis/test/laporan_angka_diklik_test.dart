import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Seluruh ANGKA di Laporan-Laporan harus dapat diklik dan memunculkan popup
/// "asal angka" -- termasuk angka SUBTOTAL dan GRAND TOTAL, bukan hanya sel data.
///
/// Versi JSP sudah menyediakannya sejak awal lewat `data-grup` dan `data-total`;
/// Desktop/Android sempat merender kedua baris itu sebagai teks biasa. Penjaga ini
/// mengunci paritasnya supaya tidak diam-diam hilang lagi saat tabelnya dirapikan.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar =
      File('lib/screens/laporan_detail_screen.dart').readAsStringSync();
  final padat = _rapat(layar);

  test('sel data angka membuka popup asal angka', () {
    expect(padat, contains(_rapat('onTap: () => _bukaRincianBaris(')));
  });

  test('angka subtotal dan grand total juga membuka popup penyusunnya', () {
    expect(padat, contains('Future<void>_bukaPenyusun('),
        reason: 'popup baris penyusun angka agregat hilang');
    // Dua pemanggilan: satu dari baris subtotal, satu dari baris grand total.
    final jumlah = '_bukaPenyusun('.allMatches(padat).length;
    expect(jumlah, greaterThanOrEqualTo(3),
        reason: 'harus ada definisi + pemakaian di subtotal DAN grand total, '
            'ditemukan $jumlah');
    expect(padat, contains(_rapat("'Subtotal \$key'")));
    expect(padat, contains(_rapat("'Grand Total \${kolom[i]['l'] ?? ''}'")));
  });

  test('popup penyusun menyebut jumlah baris dan totalnya', () {
    // Angka agregat tanpa keterangan berapa baris yang menyusunnya membuat
    // pengguna tidak bisa menilai apakah popupnya terpotong atau memang segitu.
    expect(padat, contains(_rapat('baris penyusun.')));
    expect(padat, contains(_rapat("'TOTAL (\$labelKolom)'")));
  });

  test('kanal ZKoss memakai penyusun yang sama untuk angka agregat', () {
    final zk = File(r'C:\opt\AIS\ais\src\main\src\ais\action\master\koperasi'
        r'\helper\LaporanKantinZkPanel.java');
    if (!zk.existsSync()) {
      // Working copy AIS tidak selalu tersedia di mesin CI; uji ini bersifat
      // paritas lintas-repo, jadi dilewati bila sumbernya tidak ada.
      return;
    }
    final isi = _rapat(zk.readAsStringSync());
    expect(isi, contains('privatestaticStringpenyusunRingkas('));
    expect(isi, contains(_rapat('barisSubtotal(H, grand, "Grand Total", H.baris)')));
  });
}
