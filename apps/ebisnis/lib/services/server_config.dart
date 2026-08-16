import 'package:shared_preferences/shared_preferences.dart';

import '../app_setting.dart';

/// Konfigurasi alamat server (padanan `setup.html`/`main.js` desktop-pos-electron
/// -- host/contextPath/https diisi sekali di awal lewat layar Pengaturan Alamat
/// Server, bisa diubah lagi kapan saja lewat "Ubah Alamat Server" di layar
/// Masuk). Disimpan sbg 3 kunci `SharedPreferences` terpisah (bukan satu blob
/// JSON) -- SUDAH cukup terisolasi dgn sendirinya (beda kunci = beda entri),
/// jadi tidak perlu berkas config.json terpisah spt versi Electron.
///
/// `apiBaseUrl` menggantikan `ApiClient.baseUrl` yang SEBELUMNYA hardcode
/// `https://ebisnis.id/ebisnis/Api_eBisnis` -- endpoint `/Api_eBisnis`
/// sendiri TETAP tetap (nama servlet, bukan bagian yg dikonfigurasi user),
/// hanya host+contextPath+skema yang dinamis.
class ServerConfig {
  ServerConfig._();
  static final ServerConfig instance = ServerConfig._();

  static const _kHost = 'server_host';
  static const _kContextPath = 'server_context_path';
  static const _kHttps = 'server_https';

  String host = '';
  String contextPath = '';
  bool https = true;

  bool get sudahDiatur => host.trim().isNotEmpty;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    host = sp.getString(_kHost) ?? '';
    contextPath = sp.getString(_kContextPath) ?? '';
    https = sp.getBool(_kHttps) ?? true;

    // Migrasikan HANYA alamat bawaan fase pilot yang pernah ditanam pada
    // varian Inventory & Sales/eMedik. Alamat custom pengguna tidak disentuh.
    // AppSetting.baseUrlHost == ebisnis.id menjadi penanda compile-time bahwa
    // build ini bukan varian Al-Bahjah.
    if (AppSetting.baseUrlHost == 'ebisnis.id' &&
        sanitizeHost(host).toLowerCase() == 'dev.ecampus.id' &&
        sanitizeContextPath(contextPath).toLowerCase() == 'ecampus') {
      await simpan(
        host: 'ebisnis.id',
        contextPath: 'ebisnis',
        https: true,
      );
      return;
    }

    // Migrasi versi <1.5.0 (baseUrl dulu hardcode ebisnis.id/ebisnis) --
    // perangkat yang SUDAH pernah login (ada token tersimpan) berarti sudah
    // dipakai lewat server itu; jangan tiba-tiba disuruh Pengaturan Server
    // stlh update. Instalasi baru tanpa token memakai default varian di bawah.
    if (host.trim().isEmpty && sp.getString('token') != null) {
      await simpan(host: 'ebisnis.id', contextPath: 'ebisnis', https: true);
      return;
    }
    // Varian ber-institusi tunggal dgn base URL bawaan (lihat
    // AppSetting.baseUrlHost) -- lewati layar Pengaturan Alamat Server
    // sepenuhnya sejak instalasi pertama, server sudah dikenal dari build.
    if (host.trim().isEmpty) {
      await simpan(
        host: AppSetting.baseUrlHost,
        contextPath: AppSetting.baseUrlContextPath,
        https: AppSetting.baseUrlHttps,
      );
    }
  }

  Future<void> simpan({
    required String host,
    required String contextPath,
    required bool https,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kHost, host);
    await sp.setString(_kContextPath, contextPath);
    await sp.setBool(_kHttps, https);
    this.host = host;
    this.contextPath = contextPath;
    this.https = https;
  }

  static String sanitizeHost(String raw) => raw
      .trim()
      .replaceAll(RegExp(r'^https?://', caseSensitive: false), '')
      .replaceAll(RegExp(r'/+$'), '');

  static String sanitizeContextPath(String raw) =>
      raw.trim().replaceAll(RegExp(r'^/+|/+$'), '');

  /// Host tanpa validasi ketat format domain (sengaja, sama seperti
  /// `isHostValid` Electron) -- cukup terisi dan tanpa spasi.
  static bool hostValid(String host) {
    final h = sanitizeHost(host);
    return h.isNotEmpty && !RegExp(r'\s').hasMatch(h);
  }

  String get _skema => https ? 'https' : 'http';

  /// `scheme://host/contextPath/` -- dipakai utk "Tes Koneksi" (cek server
  /// menjawab di root context path, bukan endpoint API spesifik).
  String get baseUrlTanpaEndpoint {
    final h = sanitizeHost(host);
    final c = sanitizeContextPath(contextPath);
    return '$_skema://$h${c.isNotEmpty ? '/$c' : ''}/';
  }

  /// `scheme://host/contextPath/Api_eBisnis` -- dipakai `ApiClient`.
  String get apiBaseUrl {
    final h = sanitizeHost(host);
    final c = sanitizeContextPath(contextPath);
    return '$_skema://$h${c.isNotEmpty ? '/$c' : ''}/Api_eBisnis';
  }
}
