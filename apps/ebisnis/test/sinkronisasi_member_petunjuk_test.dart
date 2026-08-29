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
    expect(source, contains("hasil['description']"));
    expect(source, contains("hasil['dilewatiDosenGuru']"));
    expect(source, contains('diproses lewat Dosen/Guru'));
    expect(source, contains('berstatus nonaktif'));
    expect(source, contains('Dosen memerlukan NIDN'));
    expect(source, contains('Guru memerlukan NIP'));
    expect(source, contains('tekan Unduh Offline'));
  });

  test('koperasi tunggal dipilih otomatis untuk sinkronisasi massal', () {
    final source =
        File('lib/screens/anggota/tab_sinkronisasi.dart').readAsStringSync();

    expect(source, contains('if (_koperasi.length == 1)'));
    expect(source, contains("_koperasi.first['id']"));
  });

  test('koperasi kosong menampilkan diagnosis backend dan memblokir sinkron',
      () {
    final source =
        File('lib/screens/anggota/tab_sinkronisasi.dart').readAsStringSync();

    expect(source, contains('Master Koperasi belum tersedia di server'));
    expect(source, contains('r78394'));
    expect(source, contains('Muat Ulang Referensi'));
    expect(source, contains('_menjalankanSemua || _koperasi.isEmpty'));
    expect(source, contains("r['error'] as String?"));
  });

  test('sinkron semua langsung menghidrasi cache dan menyegarkan daftar', () {
    final sinkron =
        File('lib/screens/anggota/tab_sinkronisasi.dart').readAsStringSync();
    final host = File('lib/screens/anggota_screen.dart').readAsStringSync();
    final data =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    final service =
        File('lib/services/sinkronisasi_tabel_service.dart').readAsStringSync();

    expect(sinkron, contains('sinkronkanAnggota()'));
    expect(sinkron, contains('member server sudah diunduh ke cache offline'));
    expect(sinkron, contains('widget.onSinkronSelesai?.call()'));
    expect(host, contains('onSinkronSelesai'));
    expect(host, contains('_versiDataMember++'));
    expect(data, contains('didUpdateWidget'));
    expect(data, contains("label: const Text('Buat dari Sivitas')"));
    expect(service, contains('Future<int> sinkronkanAnggota({'));
    expect(service, contains('replaceAnggotaCache'));
  });
}
