import 'package:flutter/services.dart';

class PosBiometricSample {
  const PosBiometricSample(this.modality, this.templateBase64,
      this.templateFormat, this.provider, this.livenessScore);
  final String modality;
  final String templateBase64;
  final String templateFormat;
  final String provider;
  final double? livenessScore;
}

/// Kontrak SDK scanner POS. Sensor bawaan Android tidak mengekspor template;
/// implementasi native harus berasal dari scanner/face-liveness institusi.
class PosBiometricCaptureBridge {
  static const _channel = MethodChannel('ais_mobile/biometric_capture');

  Future<Map<String, dynamic>> capabilities() async {
    try {
      final map =
          await _channel.invokeMapMethod<dynamic, dynamic>('capabilities');
      return map == null ? const {} : Map<String, dynamic>.from(map);
    } on MissingPluginException {
      return const {'fingerprint': false, 'face': false};
    }
  }

  Future<PosBiometricSample> capture(String modality) async {
    try {
      final map = await _channel.invokeMapMethod<dynamic, dynamic>(
          'captureProbe', {'modality': modality});
      if (map == null || '${map['templateBase64'] ?? ''}'.isEmpty) {
        throw const PosBiometricUnavailable();
      }
      return PosBiometricSample(
        '${map['modality'] ?? modality}'.toUpperCase(),
        '${map['templateBase64']}',
        '${map['templateFormat'] ?? ''}',
        '${map['provider'] ?? 'UNKNOWN'}',
        (map['livenessScore'] as num?)?.toDouble(),
      );
    } on MissingPluginException {
      throw const PosBiometricUnavailable();
    } on PlatformException catch (e) {
      throw PosBiometricUnavailable(
          e.message ?? 'Perangkat biometrik menolak proses.');
    }
  }
}

class PosBiometricUnavailable implements Exception {
  const PosBiometricUnavailable([
    this.message = 'SDK scanner fingerprint/face-liveness belum dipasang.',
  ]);
  final String message;
  @override
  String toString() => message;
}
