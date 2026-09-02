import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dasbor Draft Jurnal: "belum tersedia" dan "tidak berhak" adalah dua hal.
///
/// Dasbor ini memuat belasan modul dengan kunci menu berbeda-beda, jadi satu
/// bendera untuk seluruh layar tidak cukup. Sebelumnya `bisaPosting` hanya
/// menjawab "apakah mesinnya ada"; peran yang tidak berhak tetap ditawari tombol
/// lalu ditolak sesudah menekannya.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar =
      _rapat(File('lib/screens/draft_jurnal_screen.dart').readAsStringSync());

  test('tombol posting memeriksa hak, bukan hanya ketersediaan mesin', () {
    expect(layar, contains(_rapat("baris['bisaPosting'] != true")));
    expect(layar, contains(_rapat("baris['bolehPosting'] == false")));
  });

  test('keterangannya dibedakan, bukan dipakai ulang', () {
    // Mengatakan "belum tersedia" kepada orang yang sebenarnya hanya tidak
    // berhak adalah keterangan yang salah — ia akan melaporkannya sebagai
    // kerusakan yang tidak ada.
    expect(layar, contains(_rapat('belum tersedia dari aplikasi')));
    expect(layar, contains(_rapat('tidak berhak memposting jurnal')));
  });

  test('peladen mengirim hak per baris, bukan satu bendera untuk seluruh layar',
      () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\DraftJurnalApiHelper.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('j.put("bolehPosting"')));
    // Kunci modulnya ikut menentukan: tiap baris punya kunci menunya sendiri.
    expect(isi,
        contains(_rapat('bolehAksi(tbmuser, kunciModulBaris, "create")')));
  });
}
