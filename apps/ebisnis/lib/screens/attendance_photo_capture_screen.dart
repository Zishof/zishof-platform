import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../widgets/safe_state.dart';

/// Mengambil satu foto bukti presensi dan mengecilkannya agar memenuhi batas
/// lampiran gambar server (500 KiB). Kamera yang dipilih serta hasil foto sama
/// pada Windows dan Android.
class AttendancePhotoCaptureScreen extends StatefulWidget {
  const AttendancePhotoCaptureScreen({super.key});

  static Future<Uint8List?> ambil(BuildContext context) =>
      Navigator.of(context).push<Uint8List>(MaterialPageRoute(
          builder: (_) => const AttendancePhotoCaptureScreen()));

  @override
  State<AttendancePhotoCaptureScreen> createState() =>
      _AttendancePhotoCaptureScreenState();
}

class _AttendancePhotoCaptureScreenState
    extends State<AttendancePhotoCaptureScreen> {
  CameraController? _controller;
  bool _memuat = true, _memotret = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_siapkan());
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _siapkan() async {
    try {
      final daftar = await availableCameras();
      if (daftar.isEmpty) throw StateError('Kamera tidak ditemukan.');
      final depan =
          daftar.where((k) => k.lensDirection == CameraLensDirection.front);
      final controller = CameraController(
          depan.isEmpty ? daftar.first : depan.first, ResolutionPreset.medium,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setStateIfMounted(() {
        _controller = controller;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _error = '$e';
      });
    }
  }

  Future<void> _ambil() async {
    final controller = _controller;
    if (controller == null || _memotret) return;
    setStateIfMounted(() => _memotret = true);
    try {
      final file = await controller.takePicture();
      final asli = await file.readAsBytes();
      final decoded = img.decodeImage(asli);
      if (decoded == null) throw StateError('Foto kamera tidak dapat dibaca.');
      final resized = decoded.width > 960
          ? img.copyResize(decoded,
              width: 960, interpolation: img.Interpolation.average)
          : decoded;
      var quality = 78;
      var bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      while (bytes.length > 500 * 1024 && quality > 35) {
        quality -= 8;
        bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      }
      if (bytes.length > 500 * 1024) {
        throw StateError('Ukuran foto masih melebihi 500 KiB.');
      }
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      setStateIfMounted(() {
        _memotret = false;
        _error = 'Gagal mengambil foto: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Foto Presensi')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _controller == null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center)))
              : Column(children: [
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red))),
                  Expanded(child: Center(child: CameraPreview(_controller!))),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.icon(
                          onPressed: _memotret ? null : _ambil,
                          icon: _memotret
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.camera_alt_outlined),
                          label: Text(_memotret
                              ? 'Memproses foto…'
                              : 'Ambil Foto Presensi')))
                ]));
}
