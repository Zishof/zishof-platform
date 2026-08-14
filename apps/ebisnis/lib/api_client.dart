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

    final mulai = DateTime.now();
    final referensiPermintaan =
        '${mulai.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}-${namaAksi.hashCode.abs().toRadixString(36).toUpperCase()}';
    headers['X-Request-ID'] = referensiPermintaan;
    final batasWaktu = namaAksi == 'produk_impor_excel_preview'
        ? const Duration(minutes: 5)
        : namaAksi == 'produk_impor_excel_komit'
            ? const Duration(minutes: 3)
            : const Duration(seconds: 30);

    http.Response resp;
    try {
      resp = await http
          .post(Uri.parse(baseUrl), headers: headers, body: jsonEncode(payload))
          .timeout(batasWaktu);
    } catch (e, stack) {
      final gagal = ApiException(
        'Aplikasi belum dapat menghubungi server.',
        offline: true,
        aktivitas: namaAksi,
        kodeReferensi: referensiPermintaan,
        teknis: 'Request ID: $referensiPermintaan\n'
            'Waktu mulai: ${mulai.toIso8601String()}\n'
            'Waktu gagal: ${DateTime.now().toIso8601String()}\n'
            'Endpoint: $baseUrl\n'
            'Action: $namaAksi\n'
            'Batas waktu: ${batasWaktu.inSeconds} detik\n'
            'Exception: ${e.runtimeType}: $e\n'
            'Stack trace klien:\n$stack',
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
        kodeReferensi: referensiPermintaan,
        teknis: 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
            'Action: $namaAksi\nHTTP ${resp.statusCode}; ${e.runtimeType}: $e\n'
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
        kodeReferensi:
            '${json['referensi'] ?? json['traceId'] ?? referensiPermintaan}',
        teknis: '${json['teknis'] ?? json['technical'] ?? ''}'.trim().isEmpty
            ? 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
                'HTTP ${resp.statusCode}; action=$namaAksi; '
                'status=${json['status']}; kode=${json['kode']}; message=${json['message']}'
            : 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
                'HTTP ${resp.statusCode}; action=$namaAksi\n'
                '${json['teknis'] ?? json['technical']}',
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
  final String? kodeReferensi;

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
      this.statusHttp,
      this.kodeReferensi});

  AppErrorInfo get info {
    final dasar = AppErrorInfo.dari(
      offline ? 'network timeout: $pesan' : pesan,
      aktivitas: aktivitas,
    );
    final aktivitasPembayaran = aktivitas == 'bayar' ||
        aktivitas == 'pembayaran' ||
        (aktivitas?.endsWith('_bayar') ?? false);
    return AppErrorInfo(
      judul: aktivitasPembayaran && !offline
          ? 'Pembayaran belum berhasil'
          : dasar.judul,
      // `message` pada kontrak API memang ditujukan kepada pengguna dan
      // sudah disanitasi server. Stack/SQL tetap hanya muncul di [teknis].
      pesan: offline ? dasar.pesan : pesan,
      solusi: aktivitasPembayaran && !offline
          ? const [
              'Jangan langsung menekan Bayar berulang kali. Periksa Riwayat Penjualan dan Riwayat Sinkronisasi untuk memastikan transaksi pertama belum tercatat.',
              'Periksa kembali keranjang, metode pembayaran, nominal uang diterima, member/saldo, serta status sesi kas.',
              'Buka Informasi Teknis di bawah ini. Jika belum terselesaikan, salin seluruh detailnya dan kirimkan kepada admin/developer.',
            ]
          : dasar.solusi,
      teknis: teknis.isEmpty
          ? 'action=${aktivitas ?? '-'}; HTTP=${statusHttp ?? '-'}; $pesan'
          : teknis,
      kodeReferensi: kodeReferensi == null || kodeReferensi!.trim().isEmpty
          ? dasar.kodeReferensi
          : kodeReferensi!.trim(),
    );
  }

  @override
  String toString() => '${info.pesan} ${info.solusi.first}';
}
