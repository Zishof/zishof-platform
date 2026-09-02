import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga: mengelola Grup Pengguna & Hak Akses WAJIB admin sistem.
///
/// Gerbang lama berbunyi:
///
///     if (tbmuser != null && tbmuser.getPedagang() != null
///             && !Common.getApakahAdminLain(tbmuser)) { tolak }
///
/// yakni hanya menolak akun yang **terikat ke sebuah toko**. Syarat itu tidak
/// pernah menyaring siapa pun yang berbahaya: kolom `pedagang` nullable, dan
/// basis pengguna AIS mencakup pegawai, guru, serta dosen yang seluruhnya
/// `null` di sana. Mereka lolos, lalu dapat menulis ulang hak akses peran mana
/// pun — termasuk menjadikan dirinya supervisor.
///
/// Tidak ada lapis lain di belakangnya:
///   * `bolehAksesActionKantin` tidak memetakan `ebisnis_role_*`, jadi aksinya
///     jatuh ke `return true` di ujung metode;
///   * `PosDeviceAuthApi.terbitkanToken` menerbitkan token POS kepada akun AIS
///     **mana pun** yang kredensialnya sah (`doAutoLogin`, tanpa batasan peran).
///
/// Pesan yang ditampilkan gerbang itu sendiri sudah benar sejak semula —
/// "Hanya admin sistem yang dapat mengelola Grup Pengguna & Hak Akses" —
/// hanya kodenya yang tidak menegakkannya.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

const _akarAis = r'C:\opt\AIS\ais\src\main\src';

File _berkasAis(String relatif) =>
    File('$_akarAis${Platform.pathSeparator}'
        '${relatif.replaceAll('/', Platform.pathSeparator)}');

void main() {
  final kantin = _berkasAis('ais/action/servlet/api/KantinHelper.java');
  final posApi = _berkasAis('ais/action/servlet/PosApi.java');

  test('gerbang kelola peran tidak lagi bersyarat keterikatan toko', () {
    if (!kantin.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = kantin.readAsStringSync();
    final padat = _rapat(isi);

    // Tiga jalur: daftar peran, ambil menu peran, simpan menu peran.
    const pesan = 'Hanya admin sistem yang dapat mengelola Grup Pengguna';
    expect(pesan.allMatches(isi).length, 3,
        reason: 'jumlah jalur kelola peran berubah — tinjau ulang penjaga ini');

    expect(padat, contains(_rapat('if (!Common.getApakahAdminLain(tbmuser)) {')),
        reason: 'gerbang admin-saja tidak ditemukan');

    // Bentuk lama tidak boleh kembali: syarat getPedagang() membuat setiap akun
    // TANPA ikatan toko lolos begitu saja.
    expect(
        padat,
        isNot(contains(_rapat('if (tbmuser != null && tbmuser.getPedagang() != null'
            '&& !Common.getApakahAdminLain(tbmuser))'))),
        reason: 'gerbang kembali bersyarat keterikatan toko');
  });

  test('setiap jalur kelola peran memakai gerbang admin, bukan hanya satu', () {
    if (!kantin.existsSync()) return;
    final isi = kantin.readAsStringSync();

    // Menghitung kemunculan `!getApakahAdminLain(tbmuser)` saja TIDAK cukup:
    // pola itu dipakai lima kali di berkas ini untuk keperluan lain, sehingga
    // satu jalur boleh saja kembali bocor tanpa mengubah jumlahnya. Karena itu
    // gerbangnya diikat ke PESAN penolakannya: tiap penolakan kelola-peran
    // harus didahului gerbang admin, dan tidak boleh didahului bentuk lama.
    const pesan = 'Hanya admin sistem yang dapat mengelola Grup Pengguna';
    final titik = pesan.allMatches(isi).map((m) => m.start).toList();
    expect(titik, hasLength(3),
        reason: 'jumlah jalur kelola peran berubah — tinjau ulang penjaga ini');

    for (final t in titik) {
      final sebelum = _rapat(isi.substring((t - 400).clamp(0, t), t));
      expect(sebelum, contains(_rapat('if (!Common.getApakahAdminLain(tbmuser))')),
          reason: 'satu jalur kelola peran tidak didahului gerbang admin');
      expect(sebelum, isNot(contains(_rapat('tbmuser.getPedagang() != null'))),
          reason: 'satu jalur kelola peran kembali bersyarat keterikatan toko');
    }
  });

  test('satuan_kerja_ dipetakan di gerbang awal, tidak jatuh ke default-allow',
      () {
    if (!posApi.existsSync()) return;
    final padat = _rapat(posApi.readAsStringSync());
    // Ujung bolehAksesActionKantin adalah `return true`. Prefiks yang tidak
    // dipetakan berarti aksinya lolos lapis menu sepenuhnya — dan dua handler
    // satuan kerja (Hapus, AnggotaSimpan) bahkan tidak menerima Tbmuser,
    // sehingga tidak ada lapis kedua yang menjaga.
    expect(padat, contains(_rapat('action.startsWith("satuan_kerja_")')),
        reason: 'satuan_kerja_ kembali jatuh ke default-allow');
    // Harus berada di blok yang sama dengan saudara-saudaranya (kunci anggota).
    // Jendelanya sengaja lapang: blok ini tumbuh setiap kali ada aksi lain yang
    // ikut dipetakan ke kunci anggota (mis. daftar mutasi keuangan anggota),
    // dan jendela sempit membuat penjaga ini jatuh karena alasan yang salah.
    final i = padat.indexOf(_rapat('action.startsWith("satuan_kerja_")'));
    final sesudah = padat.substring(i, (i + 600).clamp(0, padat.length));
    expect(sesudah, contains(_rapat('menu.optBoolean("anggota"')),
        reason: 'satuan_kerja_ tidak dipetakan ke kunci menu anggota');
  });
}
