import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Manajemen Produk: tombol tulis mengikuti hak, tetapi MEMBACA tetap terbuka.
///
/// Peladen menegakkan hak `produk` lewat `KantinHelper.bolehAksiCrud` dan kini
/// mengirimkannya bersama balasan `katalog`. Yang dipadamkan hanya Tambah dan
/// Simpan — baris produk tetap dapat diketuk, karena formulirnya juga dipakai
/// untuk MELIHAT rincian; mengunci ketukannya akan menutup pembacaan, bukan
/// penyuntingan.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar =
      _rapat(File('lib/screens/produk_screen.dart').readAsStringSync());

  test('Tambah Produk mengikuti hak create', () {
    expect(layar, contains(_rapat("!_bolehProduk('create')")));
  });

  test('Simpan membedakan produk baru dari penyuntingan', () {
    // Memakai satu kunci untuk keduanya akan memberi wewenang yang tidak pernah
    // diberikan admin: boleh menambah belum tentu boleh mengubah yang sudah ada.
    expect(
        layar,
        contains(_rapat(
            "_bolehProduk(widget.produk == null ? 'create' : 'update')")));
  });

  test('ketukan baris TIDAK ikut dipadamkan', () {
    // Penjaga ini menolak perubahan yang mengunci pembacaan.
    expect(layar, isNot(contains(_rapat("onTap: _bolehProduk("))),
        reason: 'baris produk harus tetap dapat dibuka untuk dilihat');
  });

  test('hak tidak memadamkan tombol sebelum katalog dimuat', () {
    expect(layar, contains(_rapat('_hakProduk.isEmpty || _hakProduk[aksi]')));
    expect(layar, contains(_rapat('if (hakBaru is Map)')));
  });

  test('peladen mengirim hak produk bersama katalog', () {
    final f = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\PosApi.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());
    expect(isi, contains(_rapat('hasil.put("hak", hakProduk)')));
    expect(isi, contains(_rapat('"produk", "create"')));
  });
}
