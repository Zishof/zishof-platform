import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga: riwayat revisi satu baris mengikuti hak melihat barisnya sendiri.
///
/// `RevisiApiHelper` menyajikan snapshot Envers per baris lewat `revisi_daftar`
/// dan `revisi_detail`. Aturannya semula "semua pengguna login boleh melihat" —
/// masuk akal ketika daftar putih entitasnya masih berisi data produk, lalu ikut
/// terbawa ketika daftar itu tumbuh menjadi 54 entitas dan memuat data pribadi:
///
///   * `anggota` (`AnggotaKoperasi`) membawa `alamat`, `telp`, `hp`, `email`;
///   * `hotel_tamu` (`Tamu`) membawa `noIdentitas`, `alamat`, `telp`, `email`.
///
/// Penyaring `propertiSensitif` **tidak** menutupinya — dan memang tidak
/// seharusnya: tugasnya menyaring KREDENSIAL (`pin`, `*hash`, `*salt`,
/// `*token*`), bukan data pribadi.
///
/// Aksi `revisi_*` juga tidak dipetakan di `PosApi.bolehAksesActionKantin`,
/// jadi ia jatuh ke `return true` di ujung metode itu — tidak ada lapis lain.
/// Enumerasi lintas baris (`revisi_jelajah`) SUDAH admin-only sejak semula;
/// yang terbuka hanyalah riwayat satu baris yang id-nya diketahui, dan id
/// entitas di sini berupa bilangan berurutan.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

const _akarAis = r'C:\opt\AIS\ais\src\main\src';

File _berkasAis(String relatif) =>
    File('$_akarAis${Platform.pathSeparator}'
        '${relatif.replaceAll('/', Platform.pathSeparator)}');

/// Badan satu metode Java, dipotong dari kurung kurawalnya.
String _badanMetode(String src, String tandaTangan) {
  final mulai = src.indexOf(tandaTangan);
  expect(mulai, greaterThan(0), reason: 'metode tidak ditemukan: $tandaTangan');
  final buka = src.indexOf('{', mulai);
  var dalam = 0;
  for (var j = buka; j < src.length; j++) {
    if (src[j] == '{') dalam++;
    if (src[j] == '}') {
      dalam--;
      if (dalam == 0) return src.substring(buka, j);
    }
  }
  fail('kurung tidak seimbang: $tandaTangan');
}

void main() {
  final helper = _berkasAis('ais/action/servlet/api/RevisiApiHelper.java');

  test('daftar dan detail memeriksa hak melihat entitasnya', () {
    if (!helper.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final src = helper.readAsStringSync();
    for (final metode in const ['daftar', 'detail']) {
      final badan = _rapat(_badanMetode(src,
          'public static void $metode(Tbmuser tbmuser, JSONObject request'));
      expect(badan, contains(_rapat('bolehLihatRiwayat(tbmuser,')),
          reason: '$metode tidak memeriksa hak melihat entitasnya — snapshot '
              'anggota/tamu terbuka bagi setiap pengguna yang login');
    }
  });

  test('entitas berdata pribadi benar-benar terpetakan', () {
    if (!helper.existsSync()) return;
    final padat = _rapat(helper.readAsStringSync());
    // Dua inilah alasan gerbangnya ada. Kehilangan salah satunya berarti
    // gerbangnya tetap terpasang tetapi tidak lagi menjaga apa pun.
    expect(padat, contains(_rapat('"anggota"')),
        reason: 'anggota keluar dari pemetaan kunci menu');
    expect(padat, contains(_rapat('KUNCI_MENU_ENTITAS.put("hotel_tamu"')),
        reason: 'hotel_tamu keluar dari pemetaan kunci menu');
  });

  test('pemetaannya tidak menebak: kodenya harus kunci menu sungguhan', () {
    // Kunci yang salah ketik akan diam-diam meloloskan semua orang, karena
    // `menu.optBoolean(kunci, true)` mengembalikan true untuk kunci tak dikenal.
    final katalog = _berkasAis('ais/common/EbisnisMenuKatalog.java');
    if (!helper.existsSync() || !katalog.existsSync()) return;
    final daftar = RegExp(
            r'new Entri\(\s*MODUL_[A-Z_]+\s*,\s*"([a-z0-9_]+)"')
        .allMatches(katalog.readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    expect(daftar.length, greaterThan(50),
        reason: 'pembacaan DAFTAR gagal — bentuknya berubah?');

    final blok = RegExp(r'KUNCI_MENU_ENTITAS[\s\S]*?\n\t\}')
        .firstMatch(helper.readAsStringSync());
    expect(blok, isNotNull, reason: 'blok pemetaan tidak ditemukan');
    final dipakai = RegExp('"([a-z0-9_]+)"')
        .allMatches(blok!.group(0)!)
        .map((m) => m.group(1)!)
        .where((k) => k != 'hotel_tamu') // kode entitas, bukan kunci menu
        .toSet();
    for (final k in dipakai) {
      expect(daftar, contains(k),
          reason: '"$k" bukan kunci menu yang terdaftar — `optBoolean` akan '
              'mengembalikan true dan gerbangnya meloloskan semua orang');
    }
  });

  test('enumerasi lintas baris tetap admin-only', () {
    if (!helper.existsSync()) return;
    final badan = _rapat(_badanMetode(helper.readAsStringSync(),
        'public static void jelajah(Tbmuser tbmuser, JSONObject request'));
    expect(badan, contains(_rapat('!Common.getApakahAdminLain(tbmuser)')),
        reason: 'jelajah kehilangan gerbang ADMINISTRATOR-nya');
  });
}
