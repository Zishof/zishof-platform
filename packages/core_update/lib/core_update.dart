import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Info rilis terbaru dari GitHub Releases, dipakai menampilkan prompt
/// "Update Tersedia" dan auto-update komponen Windows -- lihat
/// [UpdateChecker.cekTerbaru].
class InfoUpdate {
  final String versi;
  final String catatanRilis;
  final String urlRilis;
  final String? urlApk;
  final String? urlExe;
  final String? urlPaketWindows;
  final String? sha256PaketWindows;
  const InfoUpdate({
    required this.versi,
    required this.catatanRilis,
    required this.urlRilis,
    this.urlApk,
    this.urlExe,
    this.urlPaketWindows,
    this.sha256PaketWindows,
  });
}

/// Cek rilis terbaru di GitHub Releases (padanan cek-manual `autoUpdater`
/// Electron. Pemanggil dapat memakai paket ZIP bertanda `update` untuk
/// mengganti komponen Windows secara otomatis, atau memakai aset APK/EXE
/// sebagai fallback instalasi manual.
class UpdateChecker {
  UpdateChecker._();

  /// [versiSaatIni] format "x.y.z" (tanpa build number `+n`). Mengembalikan
  /// `null` bila sudah versi terbaru, gagal jaringan, atau tak ada rilis --
  /// pemanggil TIDAK perlu membedakan alasannya, cukup anggap "tak ada
  /// pembaruan sesi ini" dan lanjut normal.
  /// [tagPrefix] -- utk VARIAN yang rilisnya bertag khusus (mis. `"apotik-"` ->
  /// tag `apotik-v1.33.0`, `"emedik-"` -> `emedik-v1.31.0`). Bila diisi, checker
  /// TIDAK memakai `releases/latest` (yang cuma satu rilis terbaru lintas semua
  /// varian -- bisa salah varian) melainkan MEMINDAI daftar rilis dan mengambil
  /// rilis ber-tag `<prefix>...` versi tertinggi. Bila null/kosong (varian yang
  /// asetnya menumpang rilis `v*` utama & dibedakan lewat [assetKeyword], spt
  /// ebisnis/albahjah/inventory_sales), perilaku lama `releases/latest` dipakai.
  static Future<InfoUpdate?> cekTerbaru({
    required String repoOwner,
    required String repoName,
    required String versiSaatIni,
    String? assetKeyword,
    String? tagPrefix,
  }) async {
    try {
      final Map<String, dynamic>? rilis;
      final prefix = tagPrefix?.trim();
      if (prefix != null && prefix.isNotEmpty) {
        rilis = await _rilisVarianTerbaru(repoOwner, repoName, prefix);
      } else {
        final resp = await http.get(
          Uri.parse(
              'https://api.github.com/repos/$repoOwner/$repoName/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        ).timeout(const Duration(seconds: 10));
        rilis = resp.statusCode == 200
            ? jsonDecode(resp.body) as Map<String, dynamic>
            : null;
      }
      if (rilis == null) return null;
      final json = rilis;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final versiTerbaru = _versiDariTag(tag);
      if (versiTerbaru.isEmpty || !_lebihBaru(versiTerbaru, versiSaatIni)) {
        return null;
      }

      final assets = (json['assets'] as List?) ?? [];
      final keyword = assetKeyword?.trim().toLowerCase();
      final urlApk = _pilihAsset(
        assets,
        ekstensi: const ['.apk'],
        keyword: keyword,
      );
      final urlExe = _pilihAsset(
        assets,
        ekstensi: const ['.exe', '.msix'],
        keyword: keyword,
      );
      final paketWindows = _pilihAssetData(
        assets,
        ekstensi: const ['.zip'],
        keyword: keyword,
        kataWajib: 'update',
      );

      return InfoUpdate(
        versi: versiTerbaru,
        catatanRilis: (json['body'] as String? ?? '').trim(),
        urlRilis: (json['html_url'] as String?) ??
            'https://github.com/$repoOwner/$repoName/releases/latest',
        urlApk: urlApk,
        urlExe: urlExe,
        urlPaketWindows: paketWindows?['browser_download_url'] as String?,
        sha256PaketWindows:
            (paketWindows?['digest'] as String?)?.replaceFirst('sha256:', ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// Pindai daftar rilis, kembalikan rilis (non-draft) ber-tag `<prefix>...`
  /// dengan versi (x.y.z dari tag) TERTINGGI. `null` bila tak ada / gagal.
  static Future<Map<String, dynamic>?> _rilisVarianTerbaru(
      String repoOwner, String repoName, String prefix) async {
    final resp = await http.get(
      Uri.parse(
          'https://api.github.com/repos/$repoOwner/$repoName/releases?per_page=50'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final list = jsonDecode(resp.body);
    if (list is! List) return null;
    Map<String, dynamic>? terbaik;
    List<int> versiTerbaik = const [0, 0, 0];
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      if (e['draft'] == true) continue;
      final tag = (e['tag_name'] as String? ?? '').trim();
      if (!tag.startsWith(prefix)) continue;
      final v = _versiDariTag(tag);
      if (v.isEmpty) continue;
      final pv = _pecahVersi(v);
      if (terbaik == null || _bandingkan(pv, versiTerbaik) > 0) {
        terbaik = e;
        versiTerbaik = pv;
      }
    }
    return terbaik;
  }

  /// Ambil `x.y.z` pertama dari tag apa pun -- menangani `v1.33.0`,
  /// `apotik-v1.33.0`, `emedik-v1.31.0` secara seragam.
  static String _versiDariTag(String tag) {
    final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tag);
    return m != null ? m.group(1)! : '';
  }

  static int _bandingkan(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i] ? 1 : -1;
    }
    return 0;
  }

  static String? _pilihAsset(
    List<dynamic> assets, {
    required List<String> ekstensi,
    String? keyword,
  }) {
    String? fallback;
    final keywordNormal = _normalisasiNamaAsset(keyword ?? '');
    for (final ekst in ekstensi) {
      for (final a in assets) {
        final m = a as Map<String, dynamic>;
        final nama = (m['name'] as String? ?? '').toLowerCase();
        final url = m['browser_download_url'] as String?;
        if (url == null) continue;
        if (!nama.endsWith(ekst)) continue;
        fallback ??= url;
        if (keywordNormal.isEmpty ||
            _normalisasiNamaAsset(nama).contains(keywordNormal)) {
          return url;
        }
      }
    }
    return fallback;
  }

  static Map<String, dynamic>? _pilihAssetData(
    List<dynamic> assets, {
    required List<String> ekstensi,
    String? keyword,
    String? kataWajib,
  }) {
    final keywordNormal = _normalisasiNamaAsset(keyword ?? '');
    final wajibNormal = _normalisasiNamaAsset(kataWajib ?? '');
    for (final a in assets) {
      if (a is! Map<String, dynamic>) continue;
      final nama = (a['name'] as String? ?? '').toLowerCase();
      final namaNormal = _normalisasiNamaAsset(nama);
      if (!ekstensi.any(nama.endsWith)) continue;
      if (keywordNormal.isNotEmpty && !namaNormal.contains(keywordNormal)) {
        continue;
      }
      if (wajibNormal.isNotEmpty && !namaNormal.contains(wajibNormal)) continue;
      if (a['browser_download_url'] is String) return a;
    }
    return null;
  }

  static String _normalisasiNamaAsset(String nilai) =>
      nilai.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _lebihBaru(String a, String b) {
    final pa = _pecahVersi(a);
    final pb = _pecahVersi(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] > pb[i];
    }
    return false;
  }

  static List<int> _pecahVersi(String v) {
    final bersih = v.split('+').first;
    final bagian = bersih.split('.');
    return List.generate(
        3, (i) => i < bagian.length ? (int.tryParse(bagian[i]) ?? 0) : 0);
  }
}

/// Mengunduh paket komponen Windows dan memverifikasi SHA-256 dari metadata
/// GitHub sebelum paket diserahkan kepada helper eksternal.
class WindowsUpdatePackage {
  WindowsUpdatePackage._();

  static Future<File> unduhDanVerifikasi({
    required String url,
    required String sha256Diharapkan,
    required String versi,
  }) async {
    final tujuan = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}pos-update-$versi.zip');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Accept'] = 'application/octet-stream';
      final response =
          await client.send(request).timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw HttpException(
            'Unduhan pembaruan gagal (${response.statusCode}).');
      }
      final sink = tujuan.openWrite();
      await response.stream.pipe(sink);
    } finally {
      client.close();
    }
    final aktual =
        (await sha256.bind(tujuan.openRead()).first).toString().toLowerCase();
    if (aktual != sha256Diharapkan.trim().toLowerCase()) {
      await tujuan.delete();
      throw const FormatException(
          'SHA-256 paket pembaruan tidak cocok. Instalasi dibatalkan.');
    }
    return tujuan;
  }
}
