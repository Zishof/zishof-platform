import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tombol cache tidak menyamar sebagai pembentukan member', () {
    final source =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();

    expect(source, contains("label: const Text('Unduh Offline')"));
    expect(source, contains('Tombol ini hanya mengunduh cache'));
    expect(source, contains('buka tab Sinkronisasi Sivitas'));
  });

  test('petunjuk sinkron sivitas menjelaskan syarat pegawai', () {
    final source =
        File('lib/screens/anggota/tab_sinkronisasi.dart').readAsStringSync();

    expect(source, contains('User ID bukan syarat'));
    expect(source, contains('Pegawai harus aktif'));
    expect(source, contains('Pegawai tanpa kode tetap didukung'));
    expect(source, contains('Dosen memerlukan NIDN'));
    expect(source, contains('Guru memerlukan NIP'));
    expect(source, contains('tekan Unduh Offline'));
  });
}
