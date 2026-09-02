import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Jurnal Umum memakai EMPAT wewenang yang terpisah, bukan satu "boleh".
///
/// Peladen memisahkannya dengan sengaja: memposting ke buku besar (`approve`)
/// bukan turunan dari boleh menyimpan draf (`create`), dan membatalkan posting
/// (`reject`) berbeda lagi. Menggabungkannya di klien akan menawarkan wewenang
/// yang tidak pernah diberikan admin.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar =
      _rapat(File('lib/screens/jurnal_umum_screen.dart').readAsStringSync());

  test('tiap tombol memakai wewenangnya sendiri', () {
    expect(layar, contains(_rapat("!_boleh('create')")), reason: 'Jurnal Baru');
    expect(layar, contains(_rapat("!_boleh('approve')")), reason: 'Posting');
    expect(layar, contains(_rapat("!_boleh('reject')")), reason: 'Batal posting');
    expect(layar, contains(_rapat("!_boleh('delete')")), reason: 'Hapus');
  });

  test('posting massal memakai wewenang yang sama dengan posting satu baris', () {
    // Kalau posting massal menumpang create, satu tombol bisa memposting seluruh
    // draf bagi orang yang hanya boleh MENYIMPAN draf.
    final n = "!_boleh('approve')".allMatches(_rapat(layar)).length;
    expect(n, greaterThanOrEqualTo(2),
        reason: 'posting per baris DAN posting massal harus keduanya bergerbang');
  });

  test('hak hanya diperbarui dari emisi server', () {
    expect(layar, contains(_rapat('if (hakBaru is Map)')));
  });

  test('peladen mengirim kelima kunci hak', () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\JurnalUmumApiHelper.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('hasil.put("hak", hakAksesJson(tbmuser))')));
    expect(isi, contains(_rapat('"create", "update", "delete", "approve", "reject"')));
  });
}
