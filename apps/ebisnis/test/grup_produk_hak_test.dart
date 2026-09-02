import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Grup Produk: visibilitas menu bukan izin mengubah.
///
/// Layar ini sudah fail-closed pada visibilitas menunya, tetapi menu yang menyala
/// tidak mengatakan apa-apa tentang boleh-tidaknya menambah, mengubah, atau
/// menghapus grup. Peladen memeriksa ketiganya terpisah.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar =
      _rapat(File('lib/screens/grup_produk_screen.dart').readAsStringSync());

  test('tiga tombol memakai haknya masing-masing', () {
    expect(layar, contains(_rapat("!_boleh('create')")), reason: 'Tambah Grup');
    expect(layar, contains(_rapat("!_boleh('update')")), reason: 'Ubah');
    expect(layar, contains(_rapat("!_boleh('delete')")), reason: 'Hapus');
  });

  test('hak hanya diperbarui dari emisi server', () {
    expect(layar, contains(_rapat('if (hakBaru is Map)')));
  });

  test('peladen menempelkan hak hanya pada daftar yang berhasil', () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\GrupProdukApiHelper.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('hasil.put("hak", hakAksesJson(tbmuser))')));
    // Menempelkan hak di atas penolakan hanya membingungkan: bila menunya mati,
    // daftar() sudah menolak lebih dulu.
    expect(isi, contains(_rapat('"00".equals(hasil.optString("status", "00"))')),
        reason: 'hak ikut tertempel walau daftarnya ditolak');
  });
}
