import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga: setiap kunci di `EbisnisMenuKatalog.KUNCI_CRUD` harus benar-benar
/// DIPERIKSA peladen.
///
/// Kunci yang terdaftar di `KUNCI_CRUD` memunculkan baris
/// create/update/delete/approve/reject di grid peran (`TbmroleAction`). Bila
/// peladen tidak pernah memeriksa aksi granular untuk kunci itu, centangnya
/// **bohong**: admin mengira sudah membatasi, padahal mencabutnya tidak
/// mengubah apa pun.
///
/// Kelas cacat kebalikannya sudah pernah terjadi dan sudah ditutup: kunci yang
/// DIPAKAI gerbang tetapi TIDAK terdaftar di `KUNCI_CRUD` membuat `bolehAksi()`
/// jatuh ke `aksiLegacy = true`, sehingga gerbangnya meloloskan setiap peran dan
/// izinnya tak pernah dapat dicabut — begitulah `returpembelian` lolos
/// (lihat docs/pos/89). Penjaga ini menjaga arah sebaliknya, yang tidak
/// meninggalkan gejala apa pun sampai ada yang mengaudit.
///
/// Enam kunci di bawah SENGAJA belum ditegakkan dari sisi eBisnis, masing-masing
/// dengan alasannya. Daftar ini adalah izin untuk TIDAK ditegakkan — bukan
/// daftar cacat yang dibiarkan. Menambah kunci baru ke `KUNCI_CRUD` tanpa
/// gerbangnya akan menjatuhkan uji ini.
const _akarAis = r'C:\opt\AIS\ais\src\main\src';

/// Kunci yang boleh tidak punya gerbang eBisnis, beserta alasannya.
const _dikecualikan = <String, String>{
  // Register obat terkendali ditulis OTOMATIS sebagai jejak audit saat obat
  // bergolongan terkendali terjual (ApotikApiHelper: ApotikNarkotikaLog).
  // Tidak ada create/update/delete yang dapat dilakukan pengguna, jadi tidak
  // ada yang bisa digerbangi. Satu-satunya pembaca lain adalah laporan.
  'apotik_narkotika': 'register audit, ditulis otomatis; tanpa mutasi pengguna',
  // Lima layar eMedik hanyalah pembungkus tipis yang menyisipkan panel ZK SIRS
  // (pagesmastersirs*zul) dan dirender DynamicJspCrudGenerator. Generator itu
  // MENEGAKKAN haknya sendiri lewat model peran AIS lama (`u.hakAkses()`),
  // bukan lewat katalog eBisnis. Menambahkan gerbang eBisnis di sana berarti
  // membangun sistem izin KEDUA untuk layar yang sudah punya satu.
  'emedik_kasir': 'panel ZK SIRS; digerbangi model hakAkses lama',
  'emedik_pendaftaran': 'panel ZK SIRS; digerbangi model hakAkses lama',
  'emedik_tagihan': 'panel ZK SIRS; digerbangi model hakAkses lama',
  'emedik_deposit': 'panel ZK SIRS; digerbangi model hakAkses lama',
  'emedik_penjamin': 'panel ZK SIRS; digerbangi model hakAkses lama',
};

/// Berkas katalog itu sendiri tidak dihitung sebagai penegak: di sanalah
/// seluruh kunci didaftarkan, jadi mencocokkannya akan selalu "berhasil".
const _bukanPenegak = <String>{
  'EbisnisMenuKatalog.java',
  'EbisnisMenuActionRegistry.java',
};

File _berkasAis(String relatif) =>
    File('$_akarAis${Platform.pathSeparator}'
        '${relatif.replaceAll('/', Platform.pathSeparator)}');

List<String> _kunciCrud(String katalog) {
  // Blok: KUNCI_CRUD = new LinkedHashSet<String>(Arrays.asList( ... ));
  final blok = RegExp(r'KUNCI_CRUD\s*=\s*new[^(]*\(([\s\S]*?)\)\);')
      .firstMatch(katalog);
  expect(blok, isNotNull, reason: 'blok KUNCI_CRUD tidak ditemukan');
  return RegExp('"([a-z0-9_]+)"')
      .allMatches(blok!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}

/// Isi setiap berkas Java yang memuat pemeriksaan aksi granular.
///
/// Disempitkan ke `ais/action`, `ais/common`, dan `ais/service` — ketiga paket
/// itulah yang memuat SELURUH 45 berkas ber-`bolehAksi`; menyapu 7.494 berkas
/// pohon penuh hanya memperlambat tanpa menambah cakupan.
List<String> _berkasPenegak() {
  final pola = RegExp(r'bolehAksi(?:Crud|Menu|Akuntansi)?\(');
  final hasil = <String>[];
  for (final paket in const ['ais/action', 'ais/common', 'ais/service']) {
    final dir = Directory(_berkasAis(paket).path);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.java')) continue;
      if (f.path.contains('${Platform.pathSeparator}.svn'
          '${Platform.pathSeparator}')) {
        continue;
      }
      if (_bukanPenegak.any((n) => f.path.endsWith(n))) continue;
      final isi = f.readAsStringSync();
      if (pola.hasMatch(isi)) hasil.add(isi);
    }
  }
  return hasil;
}

void main() {
  final katalog = _berkasAis('ais/common/EbisnisMenuKatalog.java');

  test('setiap kunci ber-CRUD benar-benar diperiksa peladen', () {
    if (!katalog.existsSync()) return; // working copy AIS tidak selalu ada
    final kunci = _kunciCrud(katalog.readAsStringSync());
    expect(kunci.length, greaterThan(50),
        reason: 'pembacaan KUNCI_CRUD gagal — daftarnya tidak masuk akal');

    final penegak = _berkasPenegak();
    expect(penegak.length, greaterThan(20),
        reason: 'tidak menemukan berkas penegak — pola pencariannya berubah?');

    final sunyi = kunci
        .where((k) => !penegak.any((isi) => isi.contains('"$k"')))
        .toList();
    final takBeralasan =
        sunyi.where((k) => !_dikecualikan.containsKey(k)).toList();

    expect(takBeralasan, isEmpty,
        reason: 'kunci ini memunculkan baris centang di grid peran, tetapi '
            'peladen tidak pernah memeriksanya — centangnya tidak mengubah '
            'apa pun: $takBeralasan');
  });

  test('daftar pengecualian tidak menyimpan kunci yang sudah tidak ada', () {
    // Pengecualian yang basi lebih berbahaya daripada tidak ada pengecualian:
    // ia diam-diam memaafkan kunci lain yang kebetulan bernama sama.
    if (!katalog.existsSync()) return;
    final kunci = _kunciCrud(katalog.readAsStringSync()).toSet();
    for (final k in _dikecualikan.keys) {
      expect(kunci, contains(k),
          reason: '$k tidak lagi ada di KUNCI_CRUD — hapus dari pengecualian');
    }
  });
}
