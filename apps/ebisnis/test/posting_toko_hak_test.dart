import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Posting Toko: melihat draf dan MENERAPKAN adalah dua kewenangan.
///
/// Peladen sudah memisahkannya dengan benar — draf boleh dilihat siapa pun yang
/// menunya tampil, menerapkan butuh hak `create` — tetapi pemisahan itu tidak
/// pernah sampai ke klien. Tombol Posting tampil sesudah draf ditampilkan, lalu
/// ditolak saat ditekan: sesudah pengguna memeriksa seluruh baris draftnya.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final dialog =
      _rapat(File('lib/screens/posting_toko_dialog.dart').readAsStringSync());

  test('kedua tombol Posting tunduk pada hak yang sama', () {
    // "Posting Semua yang Siap" dan Posting per baris memanggil aksi terapkan
    // yang sama; memadamkan salah satunya saja meninggalkan pintu terbuka.
    final n = '!_bolehTerapkan'.allMatches(dialog).length;
    expect(n, greaterThanOrEqualTo(2),
        reason: 'ditemukan $n; tombol massal DAN per baris harus keduanya');
  });

  test('haknya dibaca dari balasan draf', () {
    expect(dialog, contains(_rapat("hasil['hak']")));
    expect(dialog, contains(_rapat("_bolehTerapkan = hakBaru['create'] != false")));
  });

  test('peladen menempelkan hak pada draf, bukan pada aksi terapkan', () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\PostingKantinLanjutanHelper.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('if (!terapkan && !hasil.has("hak"))')),
        reason: 'hak harus ikut pada draf; pada aksi terapkan sudah terlambat');
    expect(isi, contains(_rapat('bolehAksiMenu(tbmuser, "posting_" + jenis, "create")')));
  });
}
