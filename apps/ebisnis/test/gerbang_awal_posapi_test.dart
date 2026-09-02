import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga: aksi yang membaca DATA KEUANGAN ANGGOTA tidak boleh jatuh ke
/// default-allow di gerbang awal `PosApi.bolehAksesActionKantin`.
///
/// Metode itu memetakan nama/prefiks aksi ke kunci menu, lalu berakhir dengan
/// `return true` — default MELOLOSKAN (hanya prefiks `si_` yang fail-closed).
/// Aksi yang tidak cocok dengan satu pun cabangnya hanya dijaga oleh helper
/// masing-masing.
///
/// Tiga daftar mutasi keuangan anggota tidak dijaga di kedua lapis:
///
///   * `mutasiTabunganList` dan `mutasiHutangList` bahkan tidak menerima
///     `Tbmuser`, jadi mustahil menegakkan izin per-pengguna;
///   * ketiganya TIDAK menyaring toko sama sekali — tanpa filter `id_anggota`
///     mereka mengembalikan mutasi tabungan/hutang/piutang SELURUH anggota
///     lintas toko, lengkap dengan nama dan nominalnya.
///
/// Token POS diterbitkan kepada akun AIS mana pun yang kredensialnya sah
/// (`PosDeviceAuthApi.terbitkanToken` → `doAutoLogin`, tanpa batasan peran),
/// sehingga "sudah lolos autentikasi" tidak menyempitkan siapa pun.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

const _akarAis = r'C:\opt\AIS\ais\src\main\src';

File _berkasAis(String relatif) =>
    File('$_akarAis${Platform.pathSeparator}'
        '${relatif.replaceAll('/', Platform.pathSeparator)}');

/// Badan metode `bolehAksesActionKantin`, dipotong dari kurung kurawalnya.
String _badanGerbang(String src) {
  final mulai = src.indexOf('private static boolean bolehAksesActionKantin');
  expect(mulai, greaterThan(0), reason: 'metode gerbang awal tidak ditemukan');
  var i = src.indexOf('{', mulai);
  var dalam = 0;
  for (var j = i; j < src.length; j++) {
    if (src[j] == '{') dalam++;
    if (src[j] == '}') {
      dalam--;
      if (dalam == 0) return src.substring(i, j);
    }
  }
  fail('kurung metode gerbang tidak seimbang');
}

void main() {
  final posApi = _berkasAis('ais/action/servlet/PosApi.java');

  test('gerbang awal masih default-allow — asumsi dasar penjaga ini', () {
    if (!posApi.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final badan = _rapat(_badanGerbang(posApi.readAsStringSync()));
    // Bila suatu saat ujungnya dibalik menjadi fail-closed, penjaga ini tidak
    // lagi diperlukan dalam bentuk sekarang — dan itu harus disadari, bukan
    // lewat begitu saja.
    expect(badan.endsWith(_rapat('return true;')), isTrue,
        reason: 'ujung gerbang berubah — tinjau ulang seluruh penjaga ini');
  });

  test('daftar keuangan anggota dipetakan, tidak jatuh ke default-allow', () {
    if (!posApi.existsSync()) return;
    final badan = _rapat(_badanGerbang(posApi.readAsStringSync()));
    for (final aksi in const [
      'mutasi_tabungan_list',
      'mutasi_hutang_list',
      'pembantu_piutang_list',
    ]) {
      expect(badan, contains(_rapat('"$aksi".equals(action)')),
          reason: '$aksi kembali jatuh ke default-allow — daftar mutasi '
              'keuangan seluruh anggota lintas toko terbuka lagi');
    }
  });

  test('ketiganya dipetakan ke kunci menu anggota, bukan sembarang kunci', () {
    if (!posApi.existsSync()) return;
    final badan = _rapat(_badanGerbang(posApi.readAsStringSync()));
    // Memetakan ke kunci yang salah sama saja membuka pintu lain: yang dijaga
    // harus benar-benar kunci menu tempat layarnya berada.
    for (final aksi in const [
      'mutasi_tabungan_list',
      'mutasi_hutang_list',
      'pembantu_piutang_list',
    ]) {
      final i = badan.indexOf(_rapat('"$aksi".equals(action)'));
      final sesudah = badan.substring(i, (i + 400).clamp(0, badan.length));
      expect(sesudah, contains(_rapat('menu.optBoolean("anggota"')),
          reason: '$aksi tidak dipetakan ke kunci menu anggota');
    }
  });

  test('satuan_kerja_ tetap terpetakan (regresi perbaikan sebelumnya)', () {
    if (!posApi.existsSync()) return;
    final badan = _rapat(_badanGerbang(posApi.readAsStringSync()));
    expect(badan, contains(_rapat('action.startsWith("satuan_kerja_")')));
  });
}
