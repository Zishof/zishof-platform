import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/pemulihan_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final voucher = CaraBayar(id: 2, nama: 'Voucher Santri', manual: false);
  final tunai = CaraBayar(id: 1, nama: 'Tunai', manual: true);
  test('voucher wajib memilih santri, Tunai umum tetap sah', () {
    expect(validasiMemberPemulihan([voucher], 2, null), isNotNull);
    expect(validasiMemberPemulihan([voucher], 2, 99), isNull);
    expect(validasiMemberPemulihan([tunai], 1, null), isNull);
  });
  test('metode lama Tunai tidak lolos izin voucher dan loading gagal tertutup',
      () {
    expect(validasiMemberPemulihan([voucher], 1, 99), isNotNull);
    expect(validasiMemberPemulihan([voucher], 2, 99, memuat: true), isNotNull);
    expect(validasiMemberPemulihan([], 1, 99), isNotNull);
  });
  test('izin kosong tidak jatuh ke daftar umum', () {
    expect(metodePemulihanMember({}), isEmpty);
    expect(
        metodePemulihanMember({
          'izinTidakDisetel': true,
          'caraBayar': [
            {'id': 1, 'nama': 'Tunai', 'manual': true}
          ]
        }),
        isEmpty);
  });
  test('payload mempertahankan ID dan nama santri; Umum tanpa identitas palsu',
      () {
    expect(identitasMemberPemulihan(Anggota.fromJson({'id': 99, 'nama': 'Member Uji'})),
        {'id_member': 99, 'nama_member': 'Member Uji'});
    expect(identitasMemberPemulihan(null), isEmpty);
  });
}

