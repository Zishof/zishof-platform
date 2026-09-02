import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tombol Pengadaan mengikuti hak akses yang dikirim peladen.
///
/// Peladen sudah menegakkan 24 pemeriksaan hak per tahap, tetapi sebelumnya
/// tidak pernah memberitahukannya kepada klien. Akibatnya seluruh tombol tampil
/// untuk semua orang dan penolakan baru terasa SESUDAH ditekan — dan karena modul
/// ini local-first, sesudah perintahnya telanjur masuk antrean: pengguna membaca
/// "tersimpan, akan dikirim otomatis" untuk pekerjaan yang justru akan ditolak.
///
/// Yang dikunci di sini adalah PEMADAMAN TOMBOL, bukan gerbangnya. Gerbang
/// sebenarnya tetap pemeriksaan di peladen; layar hanya berhenti menawarkan
/// tombol yang sudah pasti ditolak.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

String _layar(String berkas) =>
    _rapat(File('lib/screens/$berkas').readAsStringSync());

void main() {
  test('layar PR membaca hak dan memakainya di tiap aksi', () {
    final s = _layar('pengadaan_pr_screen.dart');
    expect(s, contains(_rapat("res['hak']")), reason: 'hak tidak dibaca');
    expect(s, contains(_rapat("_boleh('create')")));
    expect(s, contains(_rapat("_boleh('approve')")));
    expect(s, contains(_rapat("_boleh('reject')")));
    expect(s, contains(_rapat("_boleh('delete')")));
  });

  test('layar BAST memakai hak, dan Sinkron memakai kunci terpisah', () {
    final s = _layar('pengadaan_bast_screen.dart');
    expect(s, contains(_rapat("res['hak']")));
    expect(s, contains(_rapat("res['hakSinkron']")),
        reason: 'Sinkron ke Kulakan diatur kunci menunya sendiri '
            '(pengadaan_sinkron), bukan kunci BAST');
    expect(s, contains(_rapat('_bolehSinkron()')));
    expect(s, contains(_rapat("_boleh('create')")));
    expect(s, contains(_rapat("_boleh('delete')")));
  });

  test('empat tahap sisanya ikut memakai hak', () {
    // Kunci hak yang WAJAR untuk tiap tahap, bukan sekadar "ada _boleh(".
    const wajib = <String, List<String>>{
      'pengadaan_po_screen.dart': ['create', 'approve', 'reject', 'delete'],
      // Menerima/membatalkan tagihan MENGUBAH dokumen tahap ini, bukan membuat.
      'pengadaan_tagihan_screen.dart': ['update'],
      'pengadaan_bayar_screen.dart': ['approve'],
      // Setor membuat dokumen baru; membatalkannya membalik yang sudah terbit.
      'pengadaan_pajak_screen.dart': ['create', 'delete'],
    };
    for (final e in wajib.entries) {
      final s = _layar(e.key);
      expect(s, contains(_rapat("res['hak']")),
          reason: '${e.key} tidak membaca hak dari peladen');
      expect(s, contains(_rapat('if (hakBaru is Map)')),
          reason: '${e.key} menimpa hak tanpa memeriksa asal emisinya');
      for (final aksi in e.value) {
        expect(s, contains(_rapat("_boleh('$aksi')")),
            reason: '${e.key} tidak memakai hak $aksi');
      }
    }
  });

  test('hak hanya diperbarui dari emisi SERVER, bukan snapshot cache', () {
    // daftarCacheDulu memancarkan cache lebih dulu, dan cache TIDAK membawa hak.
    // Menimpanya dgn peta kosong akan memadamkan tombol tanpa alasan setiap kali
    // layar dibuka — persis jenis bug yang sulit dilacak karena hilang sendiri
    // begitu balasan server tiba.
    for (final berkas in [
      'pengadaan_pr_screen.dart',
      'pengadaan_bast_screen.dart',
    ]) {
      expect(_layar(berkas), contains(_rapat('if (hakBaru is Map)')),
          reason: '$berkas menimpa hak tanpa memeriksa asal emisinya');
    }
  });

  test('peladen mengirim hak pada balasan daftar tiap tahap', () {
    final helper = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api'
        r'\PengadaanPosApiHelper.java');
    if (!helper.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(helper.readAsStringSync());
    expect(isi, contains(_rapat('private static JSONObject hakAksesJson(')));
    expect(isi, contains(_rapat('hasil.put("hak", hakAksesJson(tbmuser, kunci))')));
    expect(isi, contains(_rapat('hasil.put("hakSinkron"')));
    // Ditempelkan terpusat di proses(), bukan di tujuh metode daftar terpisah.
    expect(isi, contains(_rapat('boolean tertangani = prosesAksi(')));
  });
}
