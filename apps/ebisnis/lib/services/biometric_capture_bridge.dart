import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'face_embedding_provider.dart';

class PosBiometricSample {
  const PosBiometricSample(this.modality, this.templateBase64,
      this.templateFormat, this.provider, this.livenessScore,
      {this.qualityScore});
  final String modality;
  final String templateBase64;
  final String templateFormat;
  final String provider;
  final double? livenessScore;
  final int? qualityScore;
}

/// Adapter Desktop untuk SecuGen WebAPI (SgiBioSrv).
///
/// Layanan vendor berjalan lokal melalui HTTPS. Sertifikat self-signed hanya
/// diterima untuk loopback dan tidak pernah untuk host jaringan. Template yang
/// dikembalikan adalah ISO/IEC 19794-2, bukan citra sidik jari mentah.
class SecuGenWebApiCapture {
  SecuGenWebApiCapture({
    HttpClient Function()? clientFactory,
    Uri? endpoint,
  })  : endpoint = endpoint ?? Uri.parse('https://localhost:8000/SGIFPCapture'),
        _clientFactory = clientFactory ?? HttpClient.new;

  static const templateFormat = 'ISO_19794_2';
  static const provider = 'SECUGEN_WEBAPI';

  final HttpClient Function() _clientFactory;
  final Uri endpoint;

  static bool trustedLoopback(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 8000 &&
      (uri.host == '127.0.0.1' || uri.host.toLowerCase() == 'localhost');

  Future<bool> serviceAvailable() async {
    if (!Platform.isWindows || !trustedLoopback(endpoint)) return false;
    try {
      final socket = await Socket.connect(endpoint.host, endpoint.port,
          timeout: const Duration(milliseconds: 700));
      socket.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  Future<PosBiometricSample> capture() async {
    if (!Platform.isWindows) {
      throw const PosBiometricUnavailable(
        'SecuGen WebAPI hanya digunakan pada Desktop Windows.',
      );
    }
    if (!trustedLoopback(endpoint)) {
      throw const PosBiometricUnavailable(
        'Endpoint scanner wajib HTTPS loopback pada port 8000.',
      );
    }
    final client = _clientFactory();
    client.badCertificateCallback =
        (certificate, host, port) => trustedLoopback(Uri(
              scheme: 'https',
              host: host,
              port: port,
            ));
    try {
      final request =
          await client.postUrl(endpoint).timeout(const Duration(seconds: 3));
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(Uri(queryParameters: const {
        'Timeout': '15000',
        'Quality': '50',
        'Licstr': '',
        'TemplateFormat': 'ISO',
        'FakeDetection': '1',
      }).query);
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PosBiometricUnavailable(
          'Layanan scanner SecuGen merespons HTTP ${response.statusCode}.',
        );
      }
      return parseCaptureResponse(text);
    } on PosBiometricUnavailable {
      rethrow;
    } on SocketException {
      throw const PosBiometricUnavailable(
        'SecuGen WebAPI belum aktif. Pasang driver dan jalankan SgiBioSrv.',
      );
    } on HandshakeException {
      throw const PosBiometricUnavailable(
        'Koneksi aman ke layanan scanner SecuGen gagal.',
      );
    } on Object catch (error) {
      throw PosBiometricUnavailable('Gagal membaca scanner SecuGen: $error');
    } finally {
      client.close(force: true);
    }
  }

  static PosBiometricSample parseCaptureResponse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException();
      final map = Map<String, dynamic>.from(decoded);
      final errorCode = int.tryParse('${map['ErrorCode'] ?? -1}') ?? -1;
      if (errorCode != 0) {
        throw PosBiometricUnavailable(
          'Scanner SecuGen menolak perekaman (kode $errorCode).',
        );
      }
      final template = '${map['TemplateBase64'] ?? ''}'.trim();
      final bytes = base64Decode(template);
      if (bytes.isEmpty || bytes.length > 64 * 1024) {
        throw const FormatException();
      }
      final quality = int.tryParse('${map['ImageQuality'] ?? ''}') ??
          int.tryParse('${map['NFIQ'] ?? ''}');
      return PosBiometricSample(
        'FINGERPRINT',
        template,
        templateFormat,
        provider,
        null,
        qualityScore: quality,
      );
    } on PosBiometricUnavailable {
      rethrow;
    } on Object {
      throw const PosBiometricUnavailable(
        'Respons SecuGen WebAPI tidak valid atau tidak berisi template ISO.',
      );
    }
  }
}

/// Kontrak SDK scanner POS. Sensor bawaan Android tidak mengekspor template;
/// implementasi native harus berasal dari scanner/face-liveness institusi.
class PosBiometricCaptureBridge {
  static const _channel = MethodChannel('ais_mobile/biometric_capture');

  PosBiometricCaptureBridge({SecuGenWebApiCapture? secuGen})
      : _secuGen = secuGen ?? SecuGenWebApiCapture();

  final SecuGenWebApiCapture _secuGen;

  Future<Map<String, dynamic>> capabilities() async {
    final secuGenReady = await _secuGen.serviceAvailable();
    // Provider wajah on-device (FaceOnDeviceCapture) diperiksa di sisi Dart,
    // sejajar dgn SecuGen utk fingerprint: keduanya menimpa jawaban channel
    // native karena hidup di luar plugin.
    final faceReady = await FaceOnDeviceCapture.tersedia();
    final faceProvider =
        faceReady ? FaceOnDeviceCapture.provider?.providerName : null;
    try {
      final map =
          await _channel.invokeMapMethod<dynamic, dynamic>('capabilities');
      if (map == null) {
        return {
          'fingerprint': secuGenReady,
          'face': faceReady,
          'fingerprint_provider':
              secuGenReady ? SecuGenWebApiCapture.provider : null,
          'face_provider': faceProvider,
          'reason': secuGenReady || faceReady
              ? 'Kesiapan perangkat diperiksa ulang saat perekaman.'
              : 'Plugin biometrik tidak mengembalikan kemampuan.',
        };
      }
      final result = Map<String, dynamic>.from(map);
      if (secuGenReady) {
        result['fingerprint'] = true;
        result['fingerprint_provider'] = SecuGenWebApiCapture.provider;
      }
      if (faceReady) {
        result['face'] = true;
        result['face_provider'] = faceProvider;
      }
      return result;
    } on MissingPluginException {
      return {
        'fingerprint': secuGenReady,
        'face': faceReady,
        'fingerprint_provider':
            secuGenReady ? SecuGenWebApiCapture.provider : null,
        'face_provider': faceProvider,
        'reason': secuGenReady || faceReady
            ? 'Kesiapan perangkat diperiksa ulang saat perekaman.'
            : 'Adapter SDK scanner fingerprint/face-liveness belum dipasang.',
      };
    } on PlatformException catch (error) {
      return {
        'fingerprint': false,
        'face': faceReady,
        'face_provider': faceProvider,
        'reason': error.message ?? 'Perangkat biometrik tidak dapat diperiksa.',
      };
    }
  }

  Future<PosBiometricSample> capture(String modality) async {
    if (modality.toUpperCase() == 'FINGERPRINT' &&
        await _secuGen.serviceAvailable()) {
      return _secuGen.capture();
    }
    if (modality.toUpperCase() == 'FACE' &&
        await FaceOnDeviceCapture.tersedia()) {
      return FaceOnDeviceCapture.capture();
    }
    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>(
          'captureProbe', {'modality': modality});
      if (map == null || '${map['templateBase64'] ?? ''}'.isEmpty) {
        throw const PosBiometricUnavailable();
      }
      final returnedModality = '${map['modality'] ?? modality}'.toUpperCase();
      final expectedModality = modality.toUpperCase();
      if (returnedModality != expectedModality) {
        throw PosBiometricUnavailable(
          'SDK mengembalikan modalitas $returnedModality, '
          'bukan $expectedModality.',
        );
      }
      final format = '${map['templateFormat'] ?? ''}'.trim();
      final provider = '${map['provider'] ?? ''}'.trim();
      if (format.isEmpty || provider.isEmpty) {
        throw const PosBiometricUnavailable(
          'SDK tidak menyertakan format template dan identitas provider.',
        );
      }
      final template = '${map['templateBase64']}';
      try {
        final bytes = base64Decode(template);
        if (bytes.isEmpty || bytes.length > 64 * 1024) {
          throw const FormatException();
        }
      } on FormatException {
        throw const PosBiometricUnavailable(
          'Template biometrik dari SDK tidak valid atau melebihi 64 KiB.',
        );
      }
      return PosBiometricSample(
        returnedModality,
        template,
        format,
        provider,
        (map['livenessScore'] as num?)?.toDouble(),
        qualityScore: (map['qualityScore'] as num?)?.toInt(),
      );
    } on MissingPluginException {
      throw const PosBiometricUnavailable();
    } on PlatformException catch (e) {
      throw PosBiometricUnavailable(
          e.message ?? 'Perangkat biometrik menolak proses.');
    }
  }
}

/// Menggabungkan kesiapan perangkat dengan kesiapan server. Keduanya wajib
/// diperiksa karena kamera/scanner yang tersedia belum berarti server memiliki
/// enkripsi, matcher, atau hak akses yang diperlukan.
class PosBiometricReadiness {
  const PosBiometricReadiness({
    required this.device,
    required this.server,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> server;

  bool get canManageOtherUsers => server['boleh_enroll_pengguna_lain'] == true;
  bool get serverEncryptionReady => server['server_encryption_ready'] == true;

  bool deviceReady(String modality) =>
      device[modality == 'FACE' ? 'face' : 'fingerprint'] == true;

  bool matcherReady(String modality) => modality == 'FACE'
      ? server['face_matcher_ready'] == true
      : server['fingerprint_matcher_ready'] == true;

  bool enrollmentReady(String modality) =>
      canManageOtherUsers && serverEncryptionReady && deviceReady(modality);

  bool verificationReady(String modality) =>
      serverEncryptionReady && deviceReady(modality) && matcherReady(modality);

  List<PosBiometricDiagnosticItem> diagnostics(String modality) {
    final normalized = modality.toUpperCase();
    final face = normalized == 'FACE';
    final deviceOk = deviceReady(normalized);
    final matcherOk = matcherReady(normalized);
    final providerKey = face ? 'face_provider' : 'fingerprint_provider';
    final provider = '${device[providerKey] ?? ''}'.trim();
    final deviceReason = '${device['reason'] ?? ''}'.trim();
    return [
      PosBiometricDiagnosticItem(
        'Hak perekaman pengguna lain',
        canManageOtherUsers,
        canManageOtherUsers
            ? 'Diizinkan oleh server'
            : 'Aktifkan hak enroll biometrik pada grup pengguna.',
      ),
      PosBiometricDiagnosticItem(
        'Enkripsi template di server',
        serverEncryptionReady,
        serverEncryptionReady
            ? 'Kunci enkripsi aktif'
            : 'Konfigurasikan AIS_BIOMETRIC_MASTER_KEY pada server.',
      ),
      PosBiometricDiagnosticItem(
        face ? 'Kamera + face-liveness' : 'Scanner fingerprint eksternal',
        deviceOk,
        deviceOk
            ? (provider.isEmpty ? 'Adapter perangkat siap' : provider)
            : (deviceReason.isEmpty
                ? 'SDK ${face ? 'kamera face-liveness' : 'scanner fingerprint eksternal'} belum siap.'
                : deviceReason),
      ),
      PosBiometricDiagnosticItem(
        face ? 'Matcher wajah server' : 'Matcher fingerprint server',
        matcherOk,
        matcherOk
            ? 'Matcher siap untuk verifikasi'
            : 'Pasang provider matcher yang mendukung format template perangkat.',
      ),
    ];
  }

  String reason(String modality, {required bool enrollment}) {
    if (enrollment && !canManageOtherUsers) {
      return 'Akun tidak memiliki izin mendaftarkan biometrik pengguna lain.';
    }
    if (!serverEncryptionReady) {
      return 'Kunci enkripsi biometrik server belum dikonfigurasi.';
    }
    if (!deviceReady(modality)) {
      final detail = '${device['reason'] ?? ''}'.trim();
      return detail.isEmpty
          ? 'SDK ${modality == 'FACE' ? 'kamera face-liveness' : 'scanner fingerprint eksternal'} belum siap.'
          : detail;
    }
    if (!enrollment && !matcherReady(modality)) {
      return 'Matcher ${modality == 'FACE' ? 'pengenalan wajah' : 'fingerprint'} server belum siap.';
    }
    if (enrollment && !matcherReady(modality)) {
      return 'Perekaman tersedia, tetapi matcher server belum siap untuk verifikasi.';
    }
    return 'Siap';
  }
}

class PosBiometricDiagnosticItem {
  const PosBiometricDiagnosticItem(this.label, this.ready, this.detail);

  final String label;
  final bool ready;
  final String detail;
}

class PosBiometricUnavailable implements Exception {
  const PosBiometricUnavailable([
    this.message = 'SDK scanner fingerprint/face-liveness belum dipasang.',
  ]);
  final String message;
  @override
  String toString() => message;
}
