import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tiga formulir Persediaan Apotik memakai tiga kunci menu yang BERBEDA.
///
/// Satu layar memuat Terima Barang (`apotik_pengadaan`), Opname
/// (`apotik_stok_opname`), dan Retur (`apotik_retur`). Peladen memeriksa
/// ketiganya secara terpisah, jadi memakai satu kunci untuk ketiganya akan
/// memberi wewenang yang tidak pernah diberikan admin.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar = _rapat(
      File('lib/screens/apotik/persediaan_apotik_screen.dart').readAsStringSync());

  test('tiap formulir memakai kunci menunya sendiri', () {
    for (final kunci in [
      "_bolehApotik('apotik_pengadaan', 'create')",
      "_bolehApotik('apotik_stok_opname', 'create')",
      "_bolehApotik('apotik_retur', 'create')",
    ]) {
      expect(layar, contains(_rapat(kunci)), reason: '$kunci tidak dipakai');
    }
  });

  test('tombol tidak dipadamkan sebelum hak tiba dari peladen', () {
    // Memadamkan tombol karena haknya belum sempat dimuat akan mengunci pengguna
    // yang sebenarnya berhak — dan menyala sendiri sesaat kemudian, gejala yang
    // mahal dilacak justru karena sembuh sendiri.
    expect(layar, contains(_rapat('if (_hakApotik.isEmpty) return true;')));
    expect(layar, contains(_rapat('if (hakBaru is Map)')),
        reason: 'snapshot cache tidak membawa hak; menimpanya memadamkan tombol');
  });

  test('peladen mengirim hak keempat kunci Apotik', () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\ApotikApiDispatcher.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('hasil.put("hak", hakAksesJson(tbmuser))')));
    for (final kunci in [
      'apotik_pengadaan',
      'apotik_stok_opname',
      'apotik_retur',
      'apotik_formularium',
    ]) {
      expect(isi, contains('"$kunci"'), reason: '$kunci tidak dikirim');
    }
  });
}
