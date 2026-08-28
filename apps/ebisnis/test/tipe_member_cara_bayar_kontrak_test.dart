import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kasir menghormati default dan kunci cara bayar dari Tipe Member', () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();

    expect(source, contains("hasil['caraBayarDefaultId']"));
    expect(source, contains("hasil['caraBayarTerkunci']"));
    expect(source, contains('_caraBayarDikunciTipe'));
    expect(source, contains('Icons.lock_outline'));
    expect(
        source, contains('onTap: _memuatCaraBayar || _caraBayarDikunciTipe'));
  });

  test('Tipe Member dapat mewajibkan PIN wajah dan fingerprint', () {
    final source =
        File('lib/screens/anggota/tab_tipe_member.dart').readAsStringSync();

    expect(source, contains("'wajibPin': _wajibPin"));
    expect(source, contains("'wajibBiometricWajah': _wajibBiometricWajah"));
    expect(source,
        contains("'wajibBiometricFingerprint': _wajibBiometricFingerprint"));
    expect(source, contains('Wajib pakai PIN'));
    expect(source, contains('Wajib pakai Face Recognition'));
    expect(source, contains('Wajib pakai Finger Print'));
    expect(source, contains('Default semuanya tidak aktif'));
  });

  test('Tipe Member dapat dibatasi ke banyak toko dan default ke semua toko',
      () {
    final form =
        File('lib/screens/anggota/tab_tipe_member.dart').readAsStringSync();
    final kasir = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    final sinkron =
        File('lib/services/sinkronisasi_tabel_service.dart').readAsStringSync();

    expect(form, contains("bool _berlakuSemuaToko = true"));
    expect(form, contains("'berlakuSemuaToko': _berlakuSemuaToko"));
    expect(form, contains("'daftarToko':"));
    expect(form, contains('Berlaku ke semua toko'));
    expect(form, contains('FilterChip('));
    expect(kasir, contains("'id_toko': Sesi.instance.idTokoTerpilih"));
    expect(sinkron, contains("'id_toko': Sesi.instance.idTokoTerpilih"));
  });
}
