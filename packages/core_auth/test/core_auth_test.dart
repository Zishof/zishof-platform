import 'package:core_auth/core_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uji [VerifikatorSandiLokal] -- bukti kata sandi yang membuat sesi terkunci
/// tetap dapat dibuka saat server tidak terjangkau.
///
/// Yang dijaga di sini adalah janji keamanannya, bukan sekadar "jalan": kata
/// sandi tidak pernah tersimpan, sandi salah ditolak, pengguna lain ditolak,
/// dan keluar akun benar-benar menutup jalan luring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('belum ada bukti: tidak tersedia dan tidak pernah mencocokkan', () async {
    expect(await VerifikatorSandiLokal.instance.tersedia(), isFalse);
    expect(await VerifikatorSandiLokal.instance.usernameTersimpan(), isNull);
    expect(
        await VerifikatorSandiLokal.instance.cocok('rizal', 'rahasia'), isFalse);
  });

  test('sandi yang benar cocok, yang salah tidak', () async {
    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');

    expect(await VerifikatorSandiLokal.instance.tersedia(), isTrue);
    expect(await VerifikatorSandiLokal.instance.usernameTersimpan(), 'rizal');
    expect(await VerifikatorSandiLokal.instance.cocok('rizal', 'rahasia123'),
        isTrue);
    expect(await VerifikatorSandiLokal.instance.cocok('rizal', 'rahasia124'),
        isFalse);
    expect(await VerifikatorSandiLokal.instance.cocok('rizal', ''), isFalse);
  });

  test('nama pengguna lain ditolak walau sandinya sama', () async {
    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');
    expect(await VerifikatorSandiLokal.instance.cocok('udin', 'rahasia123'),
        isFalse);
  });

  test('nama pengguna tidak peka huruf besar/kecil dan spasi tepi', () async {
    await VerifikatorSandiLokal.instance.simpan('Rizal', 'rahasia123');
    expect(await VerifikatorSandiLokal.instance.cocok('rizal', 'rahasia123'),
        isTrue);
    expect(await VerifikatorSandiLokal.instance.cocok('  RIZAL ', 'rahasia123'),
        isTrue);
  });

  test('kata sandi TIDAK tersimpan di mana pun', () async {
    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');
    final sp = await SharedPreferences.getInstance();
    for (final kunci in sp.getKeys()) {
      final nilai = sp.get(kunci);
      expect('$nilai'.contains('rahasia123'), isFalse,
          reason: 'kata sandi bocor pada kunci "$kunci"');
    }
  });

  test('garam acak: sandi sama, hash tersimpan berbeda', () async {
    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');
    final sp1 = await SharedPreferences.getInstance();
    final hash1 = sp1.getString('auth_luring_hash');
    final garam1 = sp1.getString('auth_luring_garam');

    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');
    final sp2 = await SharedPreferences.getInstance();

    expect(sp2.getString('auth_luring_garam'), isNot(garam1));
    expect(sp2.getString('auth_luring_hash'), isNot(hash1));
    // Tetap cocok walau garamnya berganti.
    expect(await VerifikatorSandiLokal.instance.cocok('rizal', 'rahasia123'),
        isTrue);
  });

  test('hapus menutup jalan luring sepenuhnya', () async {
    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');
    await VerifikatorSandiLokal.instance.hapus();

    expect(await VerifikatorSandiLokal.instance.tersedia(), isFalse);
    expect(await VerifikatorSandiLokal.instance.usernameTersimpan(), isNull);
    expect(await VerifikatorSandiLokal.instance.cocok('rizal', 'rahasia123'),
        isFalse);
    expect(await VerifikatorSandiLokal.instance.terakhirDaring(), isNull);
  });

  test('terakhirDaring tercatat saat simpan dan saat verifikasi daring',
      () async {
    await VerifikatorSandiLokal.instance.simpan('rizal', 'rahasia123');
    final pertama = await VerifikatorSandiLokal.instance.terakhirDaring();
    expect(pertama, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await VerifikatorSandiLokal.instance.catatVerifikasiDaring();
    final kedua = await VerifikatorSandiLokal.instance.terakhirDaring();
    expect(kedua!.isBefore(pertama!), isFalse);
  });
}
