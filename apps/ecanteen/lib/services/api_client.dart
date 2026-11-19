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
  static final Map<String, String> _endpointSetelahRedirect = <String, String>{};

  /// Mengirim POST JSON sambil mengikuti pengalihan HTTP -> HTTPS (301/302/307/308)
  /// pada host yang sama agar body POST dan header tidak hilang saat redirect.
  Future<http.Response> _kirimPostTahanRedirect(String url, String bodyJson) async {
    var tujuan = _endpointSetelahRedirect[url] ?? url;
    const headers = {'Content-Type': 'application/json'};
    for (var lompatan = 0; lompatan < 3; lompatan++) {
      final resp = await http
          .post(Uri.parse(tujuan), headers: headers, body: bodyJson)
          .timeout(_batasWaktu);
      final kode = resp.statusCode;
      final pindah = kode == 301 || kode == 302 || kode == 307 || kode == 308;
      final lokasi = resp.headers['location'];
      if (!pindah || lokasi == null || lokasi.trim().isEmpty) {
        return resp;
      }
      final asal = Uri.parse(tujuan);
      final baru = asal.resolve(lokasi.trim());
      if (baru.host.toLowerCase() != asal.host.toLowerCase()) {
        return resp;
      }
      tujuan = baru.toString();
      if (kode == 301 || kode == 308) {
        _endpointSetelahRedirect[url] = tujuan;
      }
    }
    return await http
        .post(Uri.parse(tujuan), headers: headers, body: bodyJson)
        .timeout(_batasWaktu);
  }

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
      res = await _kirimPostTahanRedirect(url, jsonEncode(payload));
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
