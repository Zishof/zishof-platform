import 'dart:convert';

import 'package:http/http.dart' as http;

/// Info rilis terbaru dari GitHub Releases, dipakai menampilkan prompt
/// "Update Tersedia" -- lihat [UpdateChecker.cekTerbaru].
class InfoUpdate {
  final String versi;
  final String catatanRilis;
  final String urlRilis;
  final String? urlApk;
  final String? urlExe;
  const InfoUpdate({
    required this.versi,
    required this.catatanRilis,
    required this.urlRilis,
    this.urlApk,
    this.urlExe,
  });
}

/// Cek rilis terbaru di GitHub Releases (padanan cek-manual `autoUpdater`
/// Electron, TAPI tidak mengunduh/memasang otomatis -- Flutter di sini
/// tidak dijalankan lewat installer yang bisa mengganti dirinya sendiri
/// tanpa izin tambahan, jadi alurnya: cek versi -> kalau ada yang lebih
/// baru, arahkan pengguna membuka browser ke aset rilis (APK/EXE) untuk
/// diunduh+dipasang manual, sama seperti pola distribusi proyek ini sejak
/// awal (rilis ganda APK+EXE per versi di GitHub Releases).
class UpdateChecker {
  UpdateChecker._();

  /// [versiSaatIni] format "x.y.z" (tanpa build number `+n`). Mengembalikan
  /// `null` bila sudah versi terbaru, gagal jaringan, atau tak ada rilis --
  /// pemanggil TIDAK perlu membedakan alasannya, cukup anggap "tak ada
  /// pembaruan sesi ini" dan lanjut normal.
  static Future<InfoUpdate?> cekTerbaru({
    required String repoOwner,
    required String repoName,
    required String versiSaatIni,
    String? assetKeyword,
  }) async {
    try {
      final resp = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$repoOwner/$repoName/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final versiTerbaru = tag.startsWith('v') ? tag.substring(1) : tag;
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
        ekstensi: const ['.exe', '.msix', '.zip'],
        keyword: keyword,
      );

      return InfoUpdate(
        versi: versiTerbaru,
        catatanRilis: (json['body'] as String? ?? '').trim(),
        urlRilis: (json['html_url'] as String?) ??
            'https://github.com/$repoOwner/$repoName/releases/latest',
        urlApk: urlApk,
        urlExe: urlExe,
      );
    } catch (_) {
      return null;
    }
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
