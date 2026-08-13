import 'dart:async';
import 'dart:convert';
import 'package:core_db/core_db.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/pengaturan_sesi_lokal.dart';
import 'services/server_config.dart';
import 'widgets/app_error_info.dart';

/// Klien HTTP untuk endpoint Api_eBisnis (branded alias PosApi.java, kontrak
/// JSON identik -- lihat JavaDoc ais.action.servlet.ApiEBisnis di server).
/// Satu method generik [aksi] dipakai semua layar, sama seperti pola
/// panggilPosApi/AisApi.panggil di POS Desktop/Android existing.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Dulu `static const` hardcode `https://ebisnis.id/ebisnis/Api_eBisnis` --
  /// sekarang dibangun dari [ServerConfig] (layar Pengaturan Alamat Server)
  /// supaya satu build APK/EXE bisa dipakai institusi mana pun, padanan
  /// setup.html/main.js desktop-pos-electron.
  static String get baseUrl => ServerConfig.instance.apiBaseUrl;

  String? _token;

  Future<void> muatTokenTersimpan() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
  }

  Future<void> simpanToken(String token) async {
    _token = token;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    await PengaturanSesiLokal.instance.catatAktifSekarang();
  }

  Future<void> hapusToken() async {
    _token = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await PengaturanSesiLokal.instance.hapusCatatanAktif();
  }

  bool get sudahLogin => _token != null;

  /// Memanggil satu aksi Api_eBisnis. [body] digabung dengan {action: aksi}.
  /// Melempar [ApiException] bila status bukan "success" ATAU permintaan HTTP gagal.
  Future<Map<String, dynamic>> aksi(String namaAksi,
      [Map<String, dynamic>? body]) async {
    final payload = <String, dynamic>{'action': namaAksi, ...?body};
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Bearer $_token';

    http.Response resp;
    try {
      resp = await http
          .post(Uri.parse(baseUrl), headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
    } catch (e, stack) {
      final gagal = ApiException(
        'Aplikasi belum dapat menghubungi server.',
        offline: true,
        aktivitas: namaAksi,
        teknis: '${e.runtimeType}: $e\n$stack',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e, stack) {
      final cuplikan = resp.body.length > 1200
          ? '${resp.body.substring(0, 1200)}…'
          : resp.body;
      final gagal = ApiException(
        'Jawaban server belum dapat diproses.',
        aktivitas: namaAksi,
        statusHttp: resp.statusCode,
        teknis: 'HTTP ${resp.statusCode}; ${e.runtimeType}: $e\n'
            'Response: $cuplikan\n$stack',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }

    if (json['status'] != 'success') {
      final gagal = ApiException(
        (json['message'] ?? 'Permintaan belum berhasil.') as String,
        aktivitas: namaAksi,
        statusHttp: resp.statusCode,
        teknis: 'HTTP ${resp.statusCode}; action=$namaAksi; '
            'status=${json['status']}; message=${json['message']}',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }
    return json;
  }

  Future<void> _catatKegagalan(ApiException gagal) async {
    final info = gagal.info;
    await CoreDb.instance.catatErrorLog(
      sumber: 'api:${gagal.aktivitas ?? 'unknown'}',
      tingkat: 'ERROR',
      pesan: '${info.judul}: ${info.pesan}',
      detail: 'Referensi ${info.kodeReferensi}\n${gagal.teknis}',
    );
    // Best effort: endpoint ini tidak memakai [aksi] agar kegagalan pencatatan
    // tidak memanggil dirinya sendiri tanpa akhir. Password, token, dan body
    // permintaan tidak pernah dimasukkan ke payload audit.
    try {
      await http
          .post(Uri.parse(baseUrl),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'action': 'client_error_log',
                'sumber': gagal.aktivitas ?? 'unknown',
                'pesan': info.pesan,
                'detail': gagal.teknis,
                'referensi': info.kodeReferensi,
              }))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Catatan lokal sudah tersimpan dan dapat disinkronkan/diperiksa nanti.
    }
  }

  /// Dipakai penangkap error global dan operasi lokal/non-HTTP agar seluruh
  /// exception tetap masuk error_log lokal dan, bila server tersedia, AIS.
  Future<void> catatError(Object error,
      {StackTrace? stack, String sumber = 'aplikasi'}) async {
    final gagal = ApiException(
      error.toString(),
      aktivitas: sumber,
      teknis: '${error.runtimeType}: $error${stack == null ? '' : '\n$stack'}',
    );
    await _catatKegagalan(gagal);
  }
}

class ApiException implements Exception {
  final String pesan;
  final String? aktivitas;
  final String teknis;
  final int? statusHttp;

  /// true bila kegagalan murni jaringan/timeout (server tidak terjangkau sama
  /// sekali) -- BEDA dari penolakan bisnis (status="error" dgn pesan dari
  /// server, mis. saldo kurang). Dipakai alur offline-first (KeranjangScreen)
  /// utk memutuskan "tetap simpan lokal & lanjut" (offline=true) vs "batalkan
  /// & tampilkan pesan" (offline=false).
  final bool offline;
  ApiException(this.pesan,
      {this.offline = false,
      this.aktivitas,
      this.teknis = '',
      this.statusHttp});

  AppErrorInfo get info {
    final dasar = AppErrorInfo.dari(
      offline ? 'network timeout: $pesan' : pesan,
      aktivitas: aktivitas,
    );
    return AppErrorInfo(
      judul: dasar.judul,
      pesan: dasar.pesan,
      solusi: dasar.solusi,
      teknis: teknis.isEmpty
          ? 'action=${aktivitas ?? '-'}; HTTP=${statusHttp ?? '-'}; $pesan'
          : teknis,
      kodeReferensi: dasar.kodeReferensi,
    );
  }

  @override
  String toString() => '${info.pesan} ${info.solusi.first}';
}
