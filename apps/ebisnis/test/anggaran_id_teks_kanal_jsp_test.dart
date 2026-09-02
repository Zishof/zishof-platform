import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga: id anggaran TIDAK boleh menyeberang ke JavaScript sebagai ANGKA.
///
/// Id `rab.workspace` dibangkitkan sebagai `-(Long.MAX_VALUE - n)` (lihat
/// `WorkspaceTreeModel.buatWorkspace` dan `RabImporter`), jadi selalu 19 digit —
/// jauh di atas `Number.MAX_SAFE_INTEGER` (2^53). Di JavaScript nilai sebesar
/// itu dibulatkan ke kelipatan **1.024** terdekat. Karena baris anggaran
/// bersaudara diberi id BERURUTAN, satu keluarga berisi sampai 1.024 anggaran
/// runtuh menjadi satu nilai yang sama.
///
/// Akibatnya di kanal JSP: memilih anggaran A dan anggaran B menghasilkan
/// atribut `onclick` yang identik byte-per-byte, dan nilai yang akhirnya
/// dikirim ke server bukan salah satu dari keduanya — melainkan bilangan bulat
/// ketiga yang tidak pernah ada. Penyimpanan lalu ditolak dengan "Anggaran yang
/// dipilih tidak ditemukan", atau — bila pembulatannya kebetulan mendarat pada
/// id yang sah — PR dibebankan ke anggaran YANG SALAH tanpa ada tanda apa pun.
///
/// Klien Flutter tidak terpengaruh: `int` Dart 64-bit pada build native
/// (Windows/Android). Karena itu `id` numerik TETAP dikirim; yang ditambahkan
/// adalah bentuk teks di sampingnya, untuk kanal JSP.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

const _akarAis = r'C:\opt\AIS\ais\src\main';

File _berkasAis(String relatif) => File('$_akarAis${Platform.pathSeparator}'
    '${relatif.replaceAll('/', Platform.pathSeparator)}');

void main() {
  test('presisi ganda benar-benar meruntuhkan id yang berdekatan', () {
    // Uji ini TIDAK butuh working copy AIS: ia membuktikan sebab pokoknya
    // dengan aritmetika, supaya alasan seluruh berkas ini tetap terbaca walau
    // penjaga lintas-repo di bawahnya dilewati.
    const a = -9223272037652163462; // dua id workspace bersebelahan,
    const b = -9223272037652163461; // selisihnya SATU.
    expect(a == b, isFalse, reason: 'keduanya memang id yang berbeda');

    // Inilah yang terjadi saat nilainya melewati Number di JavaScript.
    final lewatJs = <int>[a.toDouble().toInt(), b.toDouble().toInt()];
    expect(lewatJs[0], lewatJs[1],
        reason: 'dua anggaran berbeda seharusnya runtuh menjadi satu nilai — '
            'bila uji ini gagal, asumsi dasar berkas ini perlu ditinjau ulang');
    expect(lewatJs[0], isNot(a),
        reason: 'nilai hasilnya bahkan bukan salah satu id aslinya');

    // Sedangkan bentuk teksnya utuh.
    expect('$a', isNot('$b'));
  });

  test('peladen mengirimkan bentuk teks di samping angkanya', () {
    final f = _berkasAis('src/ais/action/servlet/api/PengadaanPosApiHelper.java');
    if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
    final isi = _rapat(f.readAsStringSync());

    // Daftar pilihan anggaran (dipakai form PR satuan DAN entri massal).
    expect(isi, contains(_rapat('o.put("idTeks", w.getId() == null ? ""')),
        reason: 'cariAnggaran tidak mengirim idTeks');
    // Membuka PR lama: anggaran terpilihnya dibaca dari header detail.
    expect(isi, contains(_rapat('h.put("workspace_idTeks"')),
        reason: 'detail PR tidak mengirim workspace_idTeks');

    // Bentuk angkanya SENGAJA dipertahankan untuk klien Flutter.
    expect(isi, contains(_rapat('o.put("id", w.getId())')),
        reason: 'id numerik dihapus — klien Flutter memakainya');
  });

  test('kedua JSP Pengadaan memakai bentuk teks, bukan angkanya', () {
    const jsp = <String, List<String>>{
      // berkas -> penanda yang WAJIB ada
      'webapp/WEB-INF/baru/modul/kantin/pengadaan_pr/index.jsp': [
        "+ a.idTeks +", // disisipkan ke onclick
        "el(\"prAnggaran\").value = a.idTeks;",
        "String(anggaranData[i].idTeks) !== String(id)",
        "setelAnggaranAwal(prAktif.workspace_idTeks",
      ],
      'webapp/WEB-INF/baru/modul/kantin/pengadaan_bulk/index.jsp': [
        "'<option value=\"' + a.idTeks + '\">'",
      ],
    };
    for (final e in jsp.entries) {
      final f = _berkasAis(e.key);
      if (!f.existsSync()) return; // working copy AIS tidak selalu ada di CI
      final isi = _rapat(f.readAsStringSync());
      for (final penanda in e.value) {
        expect(isi, contains(_rapat(penanda)),
            reason: '${e.key} kehilangan penanda: $penanda');
      }
    }
  });

  test('id anggaran tidak disisipkan MENTAH ke sumber JavaScript', () {
    // Bentuk lama `'(' + a.id + ')'` menaruh angka 19 digit langsung sebagai
    // literal JS. Yang menggantikannya harus dikutip (&quot;) supaya sampai ke
    // handler sebagai STRING, bukan Number.
    final f = _berkasAis(
        'webapp/WEB-INF/baru/modul/kantin/pengadaan_pr/index.jsp');
    if (!f.existsSync()) return;
    final isi = _rapat(f.readAsStringSync());
    expect(isi, isNot(contains(_rapat("+ RND + '(' + a.id + ')"))),
        reason: 'id mentah kembali disisipkan ke sumber JS');
    expect(isi, contains(_rapat("'(&quot;' + a.idTeks + '&quot;)")),
        reason: 'identitas tidak dikutip — sampai ke handler sebagai Number');
  });
}
