import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak **kunci sesi** (Lapis 1 login luring).
///
/// Yang dijaga di sini adalah satu keputusan yang mahal bila diam-diam berbalik:
/// batas waktu lokal MENGUNCI layar, **tidak** menghapus token perangkat. Token
/// berlaku 30 hari di server; membuangnya karena aplikasi lama tidak dibuka
/// membuat kasir wajib login daring pada pagi hari -- persis saat server paling
/// mungkin belum hidup -- padahal seluruh jalur luring sudah siap.
///
/// Pola source-contract mengikuti `draft_jurnal_kontrak_test.dart`: gerbang awal
/// dan ApiClient singleton tidak injectable untuk widget test, jadi yang dikunci
/// adalah bentuk kodenya di titik-titik yang menentukan.
void main() {
  final berkasGerbang = <String>['lib/main.dart', 'lib/bootstrap.dart'];

  test('gerbang awal MENGUNCI saat kedaluwarsa lokal, bukan menghapus token',
      () {
    for (final nama in berkasGerbang) {
      final source = File(nama).readAsStringSync();
      final mulai = source.indexOf('sudahKedaluwarsa()');
      expect(mulai, greaterThan(-1), reason: '$nama: cek kedaluwarsa hilang');

      // Potongan keputusan: dari pemeriksaan kedaluwarsa sampai beberapa baris
      // sesudahnya -- di situlah dulu hapusToken() dipanggil.
      final potongan = source.substring(
          mulai, (mulai + 400).clamp(0, source.length));
      expect(potongan.contains('hapusToken'), isFalse,
          reason: '$nama: token TIDAK boleh dihapus karena batas waktu lokal; '
              'batas waktu lokal hanya mengunci layar (LayarKunciScreen)');
      expect(potongan, contains('_terkunci = true'),
          reason: '$nama: kedaluwarsa lokal harus menyalakan penanda terkunci');

      expect(source, contains('LayarKunciScreen'),
          reason: '$nama: layar kunci harus dirutekan saat sesi terkunci');
    }
  });

  test('token hanya dibuang saat server menolak (401) atau keluar akun', () {
    final source = File('lib/api_client.dart').readAsStringSync();
    expect(source, contains('resp.statusCode == 401'),
        reason: 'penolakan token oleh server harus membuang sesi perangkat');
    // hapusToken membuang SATU PAKET: token, catatan aktif, dan bukti luring.
    final mulai = source.indexOf('Future<void> hapusToken()');
    expect(mulai, greaterThan(-1));
    final blok = source.substring(mulai, (mulai + 500).clamp(0, source.length));
    expect(blok, contains("sp.remove('token')"));
    expect(blok, contains('hapusCatatanAktif'));
    expect(blok, contains('VerifikatorSandiLokal.instance.hapus'),
        reason: 'identitas yang dibuang tidak boleh menyisakan jalan luring');
  });

  test('bukti sandi lokal HANYA disimpan sesudah server menerima login', () {
    final login = File('lib/screens/login_screen.dart').readAsStringSync();
    final iSimpanToken = login.indexOf('simpanToken(');
    final iSimpanBukti = login.indexOf('VerifikatorSandiLokal.instance');
    expect(iSimpanToken, greaterThan(-1));
    expect(iSimpanBukti, greaterThan(iSimpanToken),
        reason: 'bukti sandi disimpan SESUDAH token dari server diterima');
  });

  test('layar kunci: penolakan server tidak boleh dialihkan ke jalur luring',
      () {
    final source =
        File('lib/screens/layar_kunci_screen.dart').readAsStringSync();

    // Coba server dulu.
    expect(source, contains("aksi('login'"));
    // Hanya kegagalan JARINGAN yang boleh jatuh ke pemeriksaan lokal.
    expect(source, contains('if (!e.offline)'));
    expect(source, contains('_bukaLuring()'));
    // Pemeriksaan lokal wajib lewat verifikator, bukan sekadar "lanjut saja".
    expect(source, contains('VerifikatorSandiLokal.instance.cocok'));
    // Tanpa bukti lokal, buka kunci luring harus DITOLAK.
    expect(source, contains('if (!_adaBuktiLokal)'));
  });
}
