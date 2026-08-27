import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aturan biometrik jenis member dipetakan dari server dan cache', () {
    final server = Anggota.fromJson({
      'id': 7,
      'nama': 'Santri Contoh',
      'wajibPin': false,
      'wajibBiometricWajah': true,
      'wajibBiometricFingerprint': true,
    });
    expect(server.wajibBiometricWajah, isTrue);
    expect(server.wajibBiometricFingerprint, isTrue);

    final cache = Anggota.fromCache({
      'id': 7,
      'nama': 'Santri Contoh',
      'wajib_biometric_wajah': 1,
      'wajib_biometric_fingerprint': 1,
    });
    expect(cache.wajibBiometricWajah, isTrue);
    expect(cache.wajibBiometricFingerprint, isTrue);
  });

  test('checkout mengikat bukti biometrik ke kode transaksi dan ACK server',
      () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    expect(source, contains("'reference_type': 'POS_PURCHASE'"));
    expect(source, contains("'reference_id': kodeUnik"));
    expect(source, contains("'biometric_face_event_id'"));
    expect(source, contains("'biometric_fingerprint_event_id'"));
    expect(source, contains("'pin_verification_event_id'"));
    expect(source, contains(r"'clientMutationId': 'pos-pin-$kodeUnik'"));
    expect(source, contains("await ApiClient.instance.aksi('bayar', payload)"));
    expect(source, contains('Pembayaran sudah diterima server'));
  });

  test('PIN mengikuti metode pembayaran dan dialog hanya menerima angka', () {
    final source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    expect(source, contains('_pinWajibUntukMetodeTerpilih'));
    expect(source, contains('FilteringTextInputFormatter.digitsOnly'));
    expect(source, contains('GridView.count('));
    expect(source, contains('PIN numerik'));
    expect(source, contains('if (!_bisaBayar) return;'));
    expect(source, contains('if (_bisaBayar) _bayar();'));
  });

  test('aturan PIN per cara bayar mendukung satu metode dan split', () {
    final tunai = CaraBayar(
      id: 1,
      nama: 'Tunai',
      manual: true,
    );
    final voucherSantri = CaraBayar(
      id: 2,
      nama: 'Voucher Santri',
      manual: false,
      wajibPin: true,
    );
    expect(pembayaranMemerlukanPin([tunai]), isFalse);
    expect(pembayaranMemerlukanPin([voucherSantri]), isTrue);
    expect(pembayaranMemerlukanPin([tunai, voucherSantri]), isTrue);
    expect(
        CaraBayar.fromJson({
          'id': 2,
          'nama': 'Voucher Santri',
          'manual': false,
          'wajibPin': true,
        }).wajibPin,
        isTrue);
  });

  test('form Jenis dan Tipe menyimpan scope cara bayar wajib PIN', () {
    final tipe =
        File('lib/screens/anggota/tab_tipe_member.dart').readAsStringSync();
    final jenis =
        File('lib/screens/anggota/tab_jenis_member.dart').readAsStringSync();
    expect(tipe, contains('daftarCaraPembayaranWajibPin'));
    expect(jenis, contains('daftar_cara_pembayaran_wajib_pin'));
    expect(tipe, contains('kosong = semua cara bayar'));
    expect(jenis, contains('kosong = semua cara bayar'));
  });
}
