import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MitraInap: satu penampung hak untuk sembilan layar.
///
/// Peladen menegakkan 24 pemeriksaan pada delapan kunci menu, nol yang sampai ke
/// klien. Karena SELURUH layar memuat datanya lewat `muatDaftarHotel`, haknya
/// ditangkap di sana — satu tempat, sembilan layar. Menambah pembacaan hak di
/// tiap layar pasti meninggalkan layar baru tanpa gerbang.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

String _berkas(String nama) =>
    _rapat(File('lib/screens/mitrainap/$nama').readAsStringSync());

void main() {
  test('hak ditangkap di satu tempat, bukan di tiap layar', () {
    final umum = _berkas('mitrainap_common.dart');
    expect(umum, contains(_rapat('_simpanHakHotel(res)')));
    expect(umum, contains(_rapat('bool bolehHotel(String kunciMenu, String aksi)')));
  });

  test('kunci menu datang dari peladen, tidak disalin di klien', () {
    // Dua salinan tabel pemetaan aksi-ke-kunci pasti berbeda begitu salah
    // satunya diubah; klien membaca hakKunci apa adanya.
    final umum = _berkas('mitrainap_common.dart');
    expect(umum, contains(_rapat("res['hakKunci']")));
    expect(umum, isNot(contains(_rapat("startsWith('hotel_"))),
        reason: 'pemetaan aksi->kunci tidak boleh diduplikasi di klien');
  });

  test('tombol tambah memakai kunci menunya masing-masing', () {
    expect(_berkas('kamar_hotel_screen.dart'),
        contains(_rapat("bolehHotel('hotel_kamar', 'create')")));
    expect(_berkas('properti_hotel_screen.dart'),
        contains(_rapat("bolehHotel('hotel_properti', 'create')")));
  });

  test('belum dimuat berarti BOLEH, bukan padam', () {
    // Memadamkan tombol karena haknya belum tiba akan mengunci pengguna yang
    // sebenarnya berhak — dan menyala sendiri sesaat kemudian.
    expect(_berkas('mitrainap_common.dart'),
        contains(_rapat('if (hak == null) return true;')));
  });

  test('peladen mengirim hak hanya untuk aksi daftar', () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\HotelApiHelper.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('action.endsWith("_list")')));
    expect(isi, contains(_rapat('hasil.put("hakKunci", kunci)')));
  });
}
