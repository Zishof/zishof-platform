import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Klien HTTP untuk endpoint Api_eBisnis (branded alias PosApi.java, kontrak
/// JSON identik -- lihat JavaDoc ais.action.servlet.ApiEBisnis di server).
/// Satu method generik [aksi] dipakai semua layar, sama seperti pola
/// panggilPosApi/AisApi.panggil di POS Desktop/Android existing.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String baseUrl = 'https://ebisnis.id/ebisnis/Api_eBisnis';

  String? _token;

  Future<void> muatTokenTersimpan() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
  }

  Future<void> simpanToken(String token) async {
    _token = token;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
  }

  Future<void> hapusToken() async {
    _token = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
  }

  bool get sudahLogin => _token != null;

  /// Memanggil satu aksi Api_eBisnis. [body] digabung dengan {action: aksi}.
  /// Melempar [ApiException] bila status bukan "success" ATAU permintaan HTTP gagal.
  Future<Map<String, dynamic>> aksi(String namaAksi, [Map<String, dynamic>? body]) async {
    final payload = <String, dynamic>{'action': namaAksi, ...?body};
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Bearer $_token';

    http.Response resp;
    try {
      resp = await http
          .post(Uri.parse(baseUrl), headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw ApiException('Tidak bisa menghubungi server. Periksa koneksi internet Anda.', offline: true);
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('Balasan server tidak valid (HTTP ${resp.statusCode}).');
    }

    if (json['status'] != 'success') {
      throw ApiException((json['message'] ?? 'Terjadi kesalahan yang tidak diketahui.') as String);
    }
    return json;
  }
}

class ApiException implements Exception {
  final String pesan;
  /// true bila kegagalan murni jaringan/timeout (server tidak terjangkau sama
  /// sekali) -- BEDA dari penolakan bisnis (status="error" dgn pesan dari
  /// server, mis. saldo kurang). Dipakai alur offline-first (KeranjangScreen)
  /// utk memutuskan "tetap simpan lokal & lanjut" (offline=true) vs "batalkan
  /// & tampilkan pesan" (offline=false).
  final bool offline;
  ApiException(this.pesan, {this.offline = false});
  @override
  String toString() => pesan;
}
