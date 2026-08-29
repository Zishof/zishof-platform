import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/face_onnx/onnx_face_provider.dart';
import '../../widgets/safe_state.dart';

/// Layar kamera tantangan liveness dua pose: hadap lurus lalu menoleh.
///
/// Mengembalikan [FotoTantanganWajah] (dua JPEG) lewat `Navigator.pop`, atau
/// null bila dibatalkan. Layar ini TIDAK menghitung apa pun — deteksi,
/// alignment, embedding, dan skor liveness dikerjakan
/// [OnnxFaceEmbeddingProvider] supaya bisa diuji tanpa kamera.
///
/// Pola CameraController mengikuti pemindai barcode Windows core_hw yang
/// sudah terbukti jalan di webcam Desktop; paket `camera` yang sama juga
/// bekerja di Android.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  static Future<FotoTantanganWajah?> ambil(BuildContext context) {
    return Navigator.of(context).push<FotoTantanganWajah>(
      MaterialPageRoute(builder: (_) => const FaceCaptureScreen()),
    );
  }

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  CameraController? _controller;
  List<CameraDescription> _kamera = const [];
  bool _memuat = true;
  bool _memotret = false;
  String? _pesanError;

  /// Tahap 0 = hadap lurus, tahap 1 = menoleh.
  int _tahap = 0;
  XFile? _fotoFrontal;

  @override
  void initState() {
    super.initState();
    unawaited(_siapkanKamera());
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _siapkanKamera([CameraDescription? pilihan]) async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final daftar = _kamera.isEmpty ? await availableCameras() : _kamera;
      if (daftar.isEmpty) {
        throw CameraException('cameraNotFound',
            'Kamera tidak ditemukan. Hubungkan webcam lalu coba lagi.');
      }
      // Kamera depan lebih dulu bila ada (Android); Desktop biasanya hanya
      // punya webcam eksternal tanpa arah lensa.
      final depan = daftar.where(
          (k) => k.lensDirection == CameraLensDirection.front);
      final terpilih = pilihan ?? (depan.isEmpty ? daftar.first : depan.first);
      final lama = _controller;
      _controller = null;
      if (lama != null) await lama.dispose();
      final controller = CameraController(terpilih, ResolutionPreset.high,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setStateIfMounted(() {
        _kamera = daftar;
        _controller = controller;
        _memuat = false;
      });
    } on Object catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = '$e';
      });
    }
  }

  Future<void> _potret() async {
    final controller = _controller;
    if (controller == null || _memotret) return;
    setStateIfMounted(() => _memotret = true);
    try {
      final foto = await controller.takePicture();
      if (!mounted) return;
      if (_tahap == 0) {
        setStateIfMounted(() {
          _fotoFrontal = foto;
          _tahap = 1;
          _memotret = false;
        });
        return;
      }
      final frontal = await _fotoFrontal!.readAsBytes();
      final toleh = await foto.readAsBytes();
      if (!mounted) return;
      Navigator.of(context)
          .pop(FotoTantanganWajah(frontal: frontal, toleh: toleh));
    } on Object catch (e) {
      setStateIfMounted(() {
        _memotret = false;
        _pesanError = 'Gagal memotret: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi Wajah')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _siapkanKamera,
                            child: const Text('Coba lagi')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: controller == null
                          ? const SizedBox.shrink()
                          : Center(child: CameraPreview(controller)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            _tahap == 0
                                ? 'Langkah 1/2: hadapkan wajah LURUS ke '
                                    'kamera, lalu tekan Potret.'
                                : 'Langkah 2/2: MENOLEH sedikit ke kiri atau '
                                    'kanan (kepala tetap dalam bingkai), lalu '
                                    'tekan Potret.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _memotret ? null : _potret,
                            icon: _memotret
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.camera_alt_outlined),
                            label: Text(_tahap == 0
                                ? 'Potret Pose Lurus'
                                : 'Potret Pose Menoleh'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
