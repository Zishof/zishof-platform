import 'dart:convert';

import 'package:http/http.dart' as http;

import 'server_config.dart';
import 'sesi.dart';

/// Kegagalan yang sudah berbentuk pesan siap tampil untuk pengguna.
class ApiException implements Exception {
  final String pesan;
  final String? kodeStatus;
  ApiException(this.pesan, {this.kodeStatus});
  @override
  String toString() => pesan;
}

/// Pembungkus servlet `/Api`.
///
/// Seluruh aksi member memakai pola yang sama: POST JSON berisi `action`,
/// `token`, dan parameter aksi; server membalas `{status, description, ...}`
/// dengan `status == "00"` berarti berhasil (beberapa aksi lama memakai
/// `"success"`, jadi keduanya diterima -- sama seperti versi JSP).
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const Duration _batasWaktu = Duration(seconds: 30);

  /// Kirim satu aksi. [sertakanToken] dimatikan hanya untuk `login`.
  Future<Map<String, dynamic>> aksi(
    String action,
    Map<String, dynamic> parameter, {
    bool sertakanToken = true,
  }) async {
    final url = ServerConfig.instance.apiUrl;
    final payload = <String, dynamic>{'action': action, ...parameter};
    if (sertakanToken) {
      final token = Sesi.instance.token;
      if (token == null || token.isEmpty) {
        throw ApiException('Sesi Anda telah berakhir. Silakan masuk kembali.');
      }
      payload['token'] = token;
    }

    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(url),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_batasWaktu);
    } catch (e) {
      throw ApiException(
          'Tidak dapat menghubungi server.\n\nAlamat: $url\nRincian: $e');
    }

    if (res.statusCode != 200) {
      throw ApiException(
          'Server membalas kode ${res.statusCode}.\n\nAlamat: $url');
    }

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('bukan objek JSON');
      }
      body = decoded;
    } catch (e) {
      throw ApiException(
          'Balasan server tidak dapat dibaca.\n\nAlamat: $url\nRincian: $e');
    }

    final status = '${body['status'] ?? ''}';
    if (status != '00' && status != 'success') {
      final pesan = '${body['description'] ?? body['message'] ?? ''}'.trim();
      throw ApiException(
        pesan.isEmpty ? 'Permintaan ditolak server (status $status).' : pesan,
        kodeStatus: status,
      );
    }
    return body;
  }

  /// Bentuk daftar yang seragam: sebagian aksi memakai kunci `list`,
  /// sebagian `data`.
  List<Map<String, dynamic>> daftar(Map<String, dynamic> body,
      {String kunci = 'list'}) {
    final nilai = body[kunci] ?? body['list'] ?? body['data'];
    if (nilai is List) {
      return nilai
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry('$k', v)))
          .toList();
    }
    return const [];
  }
}
