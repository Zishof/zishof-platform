import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import '../biometric_capture_bridge.dart';
import '../face_embedding_provider.dart';
import 'geometri_wajah.dart';
import 'sface_pipeline.dart';
import 'yunet_decoder.dart';

/// Mesin inferensi yang bisa dipalsukan di test — implementasi nyata memakai
/// ONNX Runtime (lihat penjalan_model_ort.dart), tetapi seluruh logika
/// provider di berkas ini murni Dart dan teruji tanpa runtime native.
abstract class MesinInferensiWajah {
  /// Muat kedua model; lempar bila berkas/lisensi runtime tidak siap.
  Future<void> siapkan();

  /// Jalankan YuNet: blob NCHW BGR [1,3,h,w] -> keluaran mentah per nama
  /// ('cls_8'..'kps_32') sebagai daftar float rata.
  Future<Map<String, List<double>>> deteksi(
      Float32List blob, int lebar, int tinggi);

  /// Jalankan SFace: blob NCHW BGR [1,3,112,112] -> embedding 128 float.
  Future<List<double>> embed(Float32List blob);
}

/// Lokasi berkas model (diunduh `tool/unduh_model_wajah.ps1`; tidak di git).
class LokatorModelWajah {
  LokatorModelWajah({required this.direktoriKandidat});

  /// Default per platform: direktori kerja + samping executable (Windows
  /// release menaruh assets/face di sebelah exe), dan override lewat
  /// environment `AIS_FACE_MODEL_DIR`.
  factory LokatorModelWajah.bawaan() {
    final kandidat = <String>[
      if (Platform.environment['AIS_FACE_MODEL_DIR'] != null)
        Platform.environment['AIS_FACE_MODEL_DIR']!,
      '${Directory.current.path}${Platform.pathSeparator}assets'
          '${Platform.pathSeparator}face',
      '${File(Platform.resolvedExecutable).parent.path}'
          '${Platform.pathSeparator}assets${Platform.pathSeparator}face',
    ];
    return LokatorModelWajah(direktoriKandidat: kandidat);
  }

  static const namaSface = 'face_recognition_sface_2021dec.onnx';
  static const namaYunet = 'face_detection_yunet_2023mar.onnx';

  final List<String> direktoriKandidat;

  String? _cari(String nama) {
    for (final dir in direktoriKandidat) {
      final path = '$dir${Platform.pathSeparator}$nama';
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  String? get pathSface => _cari(namaSface);
  String? get pathYunet => _cari(namaYunet);
  bool get lengkap => pathSface != null && pathYunet != null;
}

/// Sepasang foto tantangan liveness dari UI kamera.
class FotoTantanganWajah {
  const FotoTantanganWajah({required this.frontal, required this.toleh});

  final Uint8List frontal;
  final Uint8List toleh;
}

/// Provider wajah on-device: YuNet (deteksi+landmark) -> alignment 112x112 ->
/// SFace (embedding 128-d) -> liveness tantangan dua pose.
class OnnxFaceEmbeddingProvider implements FaceEmbeddingProvider {
  OnnxFaceEmbeddingProvider({
    required this.mesin,
    required this.ambilFoto,
    this.ambangDeteksi = 0.7,
  });

  static const namaProvider = 'AIS_ONDEVICE_SFACE_V1';

  final MesinInferensiWajah mesin;

  /// Delegate UI: buka layar kamera tantangan dua pose; null = dibatalkan.
  final Future<FotoTantanganWajah?> Function() ambilFoto;

  final double ambangDeteksi;

  bool _siap = false;

  @override
  String get providerName => namaProvider;

  @override
  Future<bool> ready() async {
    if (_siap) return true;
    try {
      await mesin.siapkan();
      _siap = true;
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<PosBiometricSample> capture() async {
    if (!await ready()) {
      throw const PosBiometricUnavailable(
          'Model wajah belum siap. Jalankan tool/unduh_model_wajah.ps1.');
    }
    final foto = await ambilFoto();
    if (foto == null) {
      throw const PosBiometricUnavailable('Perekaman wajah dibatalkan.');
    }
    final frontal = await _prosesSatuPose(foto.frontal, 'pose hadap lurus');
    final toleh = await _prosesSatuPose(foto.toleh, 'pose menoleh');

    final kemiripan = cosine(frontal.embedding, toleh.embedding);
    final liveness = skorLivenessTantangan(
      yawFrontal: frontal.yaw,
      yawToleh: toleh.yaw,
      cosineAntarPose: kemiripan,
    );
    if (liveness <= 0) {
      throw const PosBiometricUnavailable(
          'Tantangan liveness gagal: gerakan menoleh tidak terdeteksi atau '
          'wajah pada kedua pose tidak konsisten. Ulangi perekaman.');
    }
    return PosBiometricSample(
      'FACE',
      base64Encode(embeddingKeBytesLe(frontal.embedding)),
      FaceOnDeviceCapture.templateFormat,
      namaProvider,
      liveness,
      qualityScore: (frontal.skorDeteksi * 100).round().clamp(0, 100),
    );
  }

  Future<_HasilPose> _prosesSatuPose(Uint8List jpeg, String label) async {
    final gambar = img.decodeImage(jpeg);
    if (gambar == null) {
      throw PosBiometricUnavailable('Foto $label tidak dapat dibaca.');
    }
    final deteksi = skalakanUntukDeteksi(gambar);
    final keluaran = await mesin.deteksi(
        blobBgrNchw(deteksi.gambar),
        deteksi.gambar.width,
        deteksi.gambar.height);
    final wajah = decodeYuNet(
      keluaran: keluaran,
      lebarInput: deteksi.gambar.width,
      tinggiInput: deteksi.gambar.height,
      ambangSkor: ambangDeteksi,
    );
    if (wajah.isEmpty) {
      throw PosBiometricUnavailable(
          'Wajah tidak terdeteksi pada $label. Posisikan wajah di dalam '
          'bingkai dgn pencahayaan cukup.');
    }
    if (wajah.length > 1) {
      throw PosBiometricUnavailable(
          'Terdeteksi lebih dari satu wajah pada $label. Pastikan hanya '
          'subjek yang direkam berada di depan kamera.');
    }
    final terbaik = wajah.first;
    final landmarkAsli = terbaik.landmark
        .map((p) => Offset(p.dx * deteksi.faktor, p.dy * deteksi.faktor))
        .toList();
    final sejajar = potongSejajarSface(gambar, landmarkAsli);
    final embedding = await mesin.embed(blobBgrNchw(sejajar));
    if (embedding.length < 4) {
      throw const PosBiometricUnavailable(
          'Model SFace mengembalikan embedding yang tidak valid.');
    }
    return _HasilPose(embedding, perkiraanYaw(landmarkAsli), terbaik.skor);
  }
}

class _HasilPose {
  const _HasilPose(this.embedding, this.yaw, this.skorDeteksi);

  final List<double> embedding;
  final double yaw;
  final double skorDeteksi;
}
