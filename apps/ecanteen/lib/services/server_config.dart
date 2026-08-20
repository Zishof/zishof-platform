import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

/// Alamat server aktif. Disimpan lokal supaya pengguna cukup mengisinya sekali.
class ServerConfig {
  ServerConfig._();
  static final ServerConfig instance = ServerConfig._();

  String host = AppConfig.hostBawaan;
  String contextPath = AppConfig.contextPathBawaan;
  bool https = AppConfig.httpsBawaan;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    host = sp.getString(AppConfig.kHost) ?? AppConfig.hostBawaan;
    contextPath =
        sp.getString(AppConfig.kContextPath) ?? AppConfig.contextPathBawaan;
    https = sp.getBool(AppConfig.kHttps) ?? AppConfig.httpsBawaan;
  }

  Future<void> simpan({
    required String host,
    required String contextPath,
    required bool https,
  }) async {
    this.host = bersihkanHost(host);
    this.contextPath = bersihkanContextPath(contextPath);
    this.https = https;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(AppConfig.kHost, this.host);
    await sp.setString(AppConfig.kContextPath, this.contextPath);
    await sp.setBool(AppConfig.kHttps, this.https);
  }

  /// Buang skema, garis miring, dan spasi supaya pengguna boleh menempel URL
  /// utuh (mis. "https://kantinpcu.ecampus.id/petra/") tanpa merusak alamat.
  static String bersihkanHost(String nilai) {
    var v = nilai.trim();
    v = v.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final garis = v.indexOf('/');
    if (garis >= 0) v = v.substring(0, garis);
    return v.trim();
  }

  static String bersihkanContextPath(String nilai) {
    var v = nilai.trim();
    v = v.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final garis = v.indexOf('/');
    if (garis >= 0) v = v.substring(garis + 1);
    while (v.startsWith('/')) {
      v = v.substring(1);
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v.trim();
  }

  String get baseUrl {
    final skema = https ? 'https' : 'http';
    final c = bersihkanContextPath(contextPath);
    return '$skema://${bersihkanHost(host)}${c.isNotEmpty ? '/$c' : ''}';
  }

  String get apiUrl => '$baseUrl/${AppConfig.endpoint}';

  /// Foto produk memakai jalur yang SAMA dgn versi JSP (lihat
  /// `checkAndLoadImage` di _beranda_anggota.jsp): servlet /Data dgn
  /// action=file + render=true. Bila produk tidak punya lampiran, server
  /// mengembalikan ikon bawaan sehingga pemanggil perlu menyiapkan fallback.
  String urlGambarProduk(Object idProduk) =>
      '$baseUrl/Data?action=file'
      '&class=ais.database.model.file.LampiranLain'
      '&ref=$idProduk'
      '&jenis=ais.database.model.inventory.Produk'
      '&render=true';

  /// Nama berkas lampiran bawaan -- dipakai JSP utk menandai "tidak ada foto".
  static const String namaGambarBawaan = 'administrator-icon_default.png';
}
