import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layar Profil Toko menulis ke SATU toko. Toko mana, ditentukan
/// [Sesi.idTokoTerpilih] -- dan urutannya bukan selera.
///
/// Kotak toko di kiri atas menampilkan nama dari `tokoFilter` bagi pengguna
/// berizin lintas toko. Kalau `idTokoTerpilih` mendahulukan `tokoId`, layar akan
/// menyunting toko yang BERBEDA dari yang tertulis di depan mata pengguna --
/// tanpa galat, tanpa tanda apa pun. Uji ini mengunci urutan itu.
void main() {
  setUp(() {
    Sesi.instance
      ..tokoId = null
      ..tokoFilter = null
      ..bolehSemuaToko = false
      ..daftarTokoFilter = const [];
  });

  test('toko pilihan pengguna mengalahkan toko bawaan akun', () {
    Sesi.instance
      ..bolehSemuaToko = true
      ..tokoId = 11
      ..tokoFilter = 22;
    expect(Sesi.instance.idTokoTerpilih, 22,
        reason: 'kotak toko menampilkan tokoFilter, jadi itulah yang disunting');
  });

  test('tanpa pilihan filter, jatuh ke toko bawaan akun', () {
    Sesi.instance
      ..tokoId = 11
      ..tokoFilter = null;
    expect(Sesi.instance.idTokoTerpilih, 11);
  });

  test('akun admin tanpa toko & masih "Semua Toko" -> null, bukan tebakan', () {
    Sesi.instance
      ..bolehSemuaToko = true
      ..tokoId = null
      ..tokoFilter = null;
    // null di sini penting: layar HARUS menolak dengan pesan yang menyuruh
    // memilih toko, bukan diam-diam memakai toko sembarang.
    expect(Sesi.instance.idTokoTerpilih, isNull);
  });

  test('akun terikat satu toko tidak terpengaruh filter yang kosong', () {
    Sesi.instance
      ..bolehSemuaToko = false
      ..tokoId = 7
      ..tokoFilter = null;
    expect(Sesi.instance.idTokoTerpilih, 7);
  });

  test('nama toko yang ditampilkan cocok dgn id yang akan dikirim', () {
    Sesi.instance
      ..bolehSemuaToko = true
      ..tokoId = 11
      ..tokoFilter = 22
      ..daftarTokoFilter = const [
        {'id': 11, 'nama': 'CE LAMA'},
        {'id': 22, 'nama': 'CE NDUTT'},
      ];
    // Inilah inti bug yang diperbaiki: yang TERTULIS dan yang TERKIRIM harus
    // menunjuk toko yang sama.
    expect(Sesi.instance.namaTokoFilter, 'CE NDUTT');
    expect(Sesi.instance.idTokoTerpilih, 22);
  });
}
