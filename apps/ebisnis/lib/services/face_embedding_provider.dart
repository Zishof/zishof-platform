import 'dart:convert';
import 'dart:typed_data';

import 'biometric_capture_bridge.dart';

/// <h3>Seam provider embedding wajah on-device.</h3>
///
/// Server AIS mencocokkan wajah lewat cosine similarity atas embedding
/// `FACE_EMBEDDING_F32_LE_V1` (float32 little-endian, matcher bawaan
/// `AIS_COSINE_FACE_V1` — lihat BiometricMatcherRegistry.java). Klien-lah
/// yang wajib menghasilkan embedding itu: server SENGAJA tidak menerima foto
/// mentah (JPEG/PNG bukan template pengenalan wajah).
///
/// Kelas ini adalah SEAM-nya: implementasi nyata (MobileFaceNet/TFLite +
/// deteksi-alignment wajah + liveness aktif berbasis tantangan kedip/toleh)
/// dipasang lewat [FaceOnDeviceCapture.pasang] saat startup varian. Selama
/// belum ada implementasi terpasang, kemampuan wajah tetap FAIL-CLOSED —
/// jangan pernah memalsukan `face: true` tanpa embedder sungguhan.
abstract class FaceEmbeddingProvider {
  /// Nama provider yang ikut tercatat di audit server (mis.
  /// 'AIS_ONDEVICE_FACE_V1'). Wajib stabil antar-rilis.
  String get providerName;

  /// true hanya bila model termuat DAN kamera dapat dipakai sekarang.
  Future<bool> ready();

  /// Jalankan capture penuh: deteksi wajah -> tantangan liveness ->
  /// embedding float32 LE. Lempar [PosBiometricUnavailable] dengan pesan
  /// yang bisa dibaca kasir bila ada tahap yang gagal.
  Future<PosBiometricSample> capture();
}

/// Registri provider wajah on-device + validasi kontrak embedding.
class FaceOnDeviceCapture {
  FaceOnDeviceCapture._();

  /// Format satu-satunya yang dicocokkan matcher bawaan server.
  static const templateFormat = 'FACE_EMBEDDING_F32_LE_V1';

  static FaceEmbeddingProvider? _provider;

  /// Pasang implementasi provider (dipanggil sekali saat startup varian).
  /// null utk melepas (test/teardown).
  static void pasang(FaceEmbeddingProvider? provider) {
    _provider = provider;
  }

  static FaceEmbeddingProvider? get provider => _provider;

  static Future<bool> tersedia() async {
    final p = _provider;
    if (p == null) return false;
    try {
      return await p.ready();
    } on Object {
      return false;
    }
  }

  /// Capture lewat provider terpasang, lalu VALIDASI hasilnya terhadap
  /// kontrak server sebelum dikirim — provider yang salah format harus
  /// gagal di perangkat, bukan diam-diam ditolak matcher.
  static Future<PosBiometricSample> capture() async {
    final p = _provider;
    if (p == null) {
      throw const PosBiometricUnavailable(
        'Provider kamera face-liveness belum dipasang pada build ini.',
      );
    }
    final sample = await p.capture();
    if (sample.modality.toUpperCase() != 'FACE') {
      throw PosBiometricUnavailable(
          'Provider wajah mengembalikan modalitas ${sample.modality}.');
    }
    if (sample.templateFormat != templateFormat) {
      throw PosBiometricUnavailable(
          'Format ${sample.templateFormat} tidak cocok dgn matcher server '
          '($templateFormat).');
    }
    final galat = validasiEmbeddingBase64(sample.templateBase64);
    if (galat != null) throw PosBiometricUnavailable(galat);
    if (sample.livenessScore == null) {
      throw const PosBiometricUnavailable(
        'Provider wajah tidak menyertakan skor liveness — wajib ada; foto '
        'diam tanpa liveness bukan bukti biometrik.',
      );
    }
    return sample;
  }

  /// Cermin validasi matcher server (BiometricMatcherRegistry.matchFace):
  /// float32 LE, panjang kelipatan 4, minimal 16 byte (4 dimensi), maksimal
  /// 64 KiB, tanpa NaN/Infinity. Return null bila sah, atau pesan galat.
  static String? validasiEmbeddingBase64(String base64) {
    Uint8List bytes;
    try {
      bytes = base64Decode(base64.trim());
    } on FormatException {
      return 'Embedding wajah bukan Base64 yang sah.';
    }
    if (bytes.length < 16 || bytes.length % 4 != 0) {
      return 'Embedding wajah harus float32 (kelipatan 4 byte, minimal 16).';
    }
    if (bytes.length > 64 * 1024) {
      return 'Embedding wajah melebihi 64 KiB.';
    }
    final angka = bytes.buffer
        .asByteData(bytes.offsetInBytes, bytes.length);
    var adaNonNol = false;
    for (var i = 0; i < bytes.length; i += 4) {
      final v = angka.getFloat32(i, Endian.little);
      if (v.isNaN || v.isInfinite) {
        return 'Embedding wajah mengandung NaN/Infinity.';
      }
      if (v != 0) adaNonNol = true;
    }
    if (!adaNonNol) {
      return 'Embedding wajah bernilai nol semua — model belum menghasilkan '
          'vektor yang berarti.';
    }
    return null;
  }
}
