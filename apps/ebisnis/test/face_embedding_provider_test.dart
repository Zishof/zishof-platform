import 'dart:convert';
import 'dart:typed_data';

import 'package:ebisnis/services/biometric_capture_bridge.dart';
import 'package:ebisnis/services/face_embedding_provider.dart';
import 'package:flutter_test/flutter_test.dart';

String _embeddingBase64(List<double> nilai) {
  final data = Float32List.fromList(nilai.map((e) => e.toDouble()).toList());
  final bytes = data.buffer.asUint8List();
  // Float32List menyimpan sesuai endian host; matcher server membaca little-
  // endian. Tulis ulang eksplisit LE supaya test tidak bergantung host.
  final le = ByteData(bytes.length);
  for (var i = 0; i < data.length; i++) {
    le.setFloat32(i * 4, data[i], Endian.little);
  }
  return base64Encode(le.buffer.asUint8List());
}

class _ProviderPalsu implements FaceEmbeddingProvider {
  _ProviderPalsu(this.sample, {this.siap = true});
  final PosBiometricSample sample;
  final bool siap;

  @override
  String get providerName => 'FAKE_FACE_V1';

  @override
  Future<bool> ready() async => siap;

  @override
  Future<PosBiometricSample> capture() async => sample;
}

PosBiometricSample _sampelSah({String? format, double? liveness = 0.93}) =>
    PosBiometricSample(
      'FACE',
      _embeddingBase64(List<double>.generate(128, (i) => (i % 7) * 0.13 + 0.01)),
      format ?? FaceOnDeviceCapture.templateFormat,
      'FAKE_FACE_V1',
      liveness,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => FaceOnDeviceCapture.pasang(null));

  // Endpoint di luar port 8000 membuat trustedLoopback false sehingga
  // serviceAvailable() SecuGen kembali false SEKETIKA tanpa membuka socket —
  // wajib di test: socket sungguhan menggantung di zona fake-async.
  PosBiometricCaptureBridge bridgeTanpaScanner() => PosBiometricCaptureBridge(
      secuGen: SecuGenWebApiCapture(endpoint: Uri.parse('https://127.0.0.1:1')));

  group('validasi embedding (cermin matcher server)', () {
    test('embedding 128-float LE sah', () {
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              _embeddingBase64(List<double>.generate(128, (i) => i * 0.01 + 0.001))),
          isNull);
    });

    test('bukan Base64 ditolak', () {
      expect(FaceOnDeviceCapture.validasiEmbeddingBase64('!!bukan-base64!!'),
          contains('Base64'));
    });

    test('panjang bukan kelipatan 4 / terlalu pendek ditolak', () {
      expect(FaceOnDeviceCapture.validasiEmbeddingBase64(base64Encode([1, 2, 3])),
          contains('float32'));
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              base64Encode(List.filled(12, 7))),
          contains('float32'));
    });

    test('NaN/Infinity ditolak', () {
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              _embeddingBase64([0.5, double.nan, 0.25, 0.75])),
          contains('NaN'));
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              _embeddingBase64([0.5, double.infinity, 0.25, 0.75])),
          contains('NaN'));
    });

    test('vektor nol semua ditolak', () {
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              _embeddingBase64(List.filled(64, 0.0))),
          contains('nol'));
    });

    test('melebihi 64 KiB ditolak', () {
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              base64Encode(List.filled(64 * 1024 + 4, 1))),
          contains('64 KiB'));
    });
  });

  group('fail-closed tanpa provider', () {
    test('tersedia() false dan capture melempar', () async {
      expect(await FaceOnDeviceCapture.tersedia(), isFalse);
      expect(FaceOnDeviceCapture.capture(),
          throwsA(isA<PosBiometricUnavailable>()));
    });
  });

  group('provider terpasang', () {
    test('sampel sah diteruskan', () async {
      FaceOnDeviceCapture.pasang(_ProviderPalsu(_sampelSah()));
      expect(await FaceOnDeviceCapture.tersedia(), isTrue);
      final hasil = await FaceOnDeviceCapture.capture();
      expect(hasil.templateFormat, FaceOnDeviceCapture.templateFormat);
      expect(hasil.livenessScore, isNotNull);
    });

    test('format selain FACE_EMBEDDING_F32_LE_V1 ditolak di perangkat',
        () async {
      FaceOnDeviceCapture.pasang(
          _ProviderPalsu(_sampelSah(format: 'JPEG_BASE64')));
      expect(FaceOnDeviceCapture.capture(),
          throwsA(isA<PosBiometricUnavailable>()));
    });

    test('tanpa skor liveness ditolak', () async {
      FaceOnDeviceCapture.pasang(_ProviderPalsu(_sampelSah(liveness: null)));
      expect(FaceOnDeviceCapture.capture(),
          throwsA(isA<PosBiometricUnavailable>()));
    });

    test('provider belum siap -> tersedia() false', () async {
      FaceOnDeviceCapture.pasang(_ProviderPalsu(_sampelSah(), siap: false));
      expect(await FaceOnDeviceCapture.tersedia(), isFalse);
    });
  });

  group('integrasi bridge', () {
    test('capabilities melaporkan face + provider saat terpasang', () async {
      FaceOnDeviceCapture.pasang(_ProviderPalsu(_sampelSah()));
      final cap = await bridgeTanpaScanner().capabilities();
      expect(cap['face'], isTrue);
      expect(cap['face_provider'], 'FAKE_FACE_V1');
    });

    test('capture FACE dirutekan ke provider on-device', () async {
      FaceOnDeviceCapture.pasang(_ProviderPalsu(_sampelSah()));
      final hasil = await bridgeTanpaScanner().capture('FACE');
      expect(hasil.provider, 'FAKE_FACE_V1');
      expect(hasil.modality, 'FACE');
    });

    test('tanpa provider, capabilities tetap face: false', () async {
      final cap = await bridgeTanpaScanner().capabilities();
      expect(cap['face'], isFalse,
          reason: 'fail-closed: jangan pernah memalsukan kesiapan wajah');
    });
  });
}
