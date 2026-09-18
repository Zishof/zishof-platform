import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metode Kasbon (masukSebagaiHutang) wajib memiliki PIC dan masuk verifikasi piutang', () {
    final kasbon = CaraBayar.fromJson({
      'id': 101,
      'kode': 'KASBON_DIVISI',
      'nama': 'Kasbon Divisi',
      'manual': true,
      'masukSebagaiHutang': true,
      'wajibPilihMember': true,
    });

    expect(kasbon.masukSebagaiHutang, isTrue);
    expect(kasbon.wajibPilihMember, isTrue);
    expect(kasbon.memotongDepositEfektif, isFalse);
  });

  test('kontrak keranjang_screen mengikat _hutangAkanDipakai ke _verifikasiMemberWajibServer', () {
    final keranjang = File('lib/screens/keranjang_screen.dart').readAsStringSync();

    expect(keranjang, contains('bool get _hutangAkanDipakai'));
    expect(keranjang, contains('masukSebagaiHutang'));
    expect(keranjang, contains('_hutangAkanDipakai'));
    expect(keranjang, contains('_verifikasiMemberWajibServer'));

    final polaVerifikasi = RegExp(
      r'bool get _verifikasiMemberWajibServer\s*\{\s*final member = _memberTerpilih;\s*return member != null &&\s*\([^;]*_hutangAkanDipakai[^;]*\);',
      multiLine: true,
    );
    expect(polaVerifikasi.hasMatch(keranjang), isTrue,
      reason: 'Kasbon wajib diverifikasi secara online ke server dan tidak boleh lolos offline.');
  });
}