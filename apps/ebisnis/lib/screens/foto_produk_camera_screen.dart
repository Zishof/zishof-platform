import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../widgets/safe_state.dart';

/// Kamera foto produk lintas Windows/Android.
///
/// `image_picker` desktop hanya membuka file selector dan tidak menyediakan
/// implementasi `ImageSource.camera`. Aplikasi sudah membawa plugin `camera`
/// + `camera_windows`, jadi pengambilan foto dilakukan langsung di layar ini.
class FotoProdukCameraScreen extends StatefulWidget {
  const FotoProdukCameraScreen({super.key, this.judul = 'Ambil Foto Produk'});

  final String judul;

  static Future<XFile?> ambil(BuildContext context,
      {String judul = 'Ambil Foto Produk'}) {
    return Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => FotoProdukCameraScreen(judul: judul)),
    );
  }

  @override
  State<FotoProdukCameraScreen> createState() => _FotoProdukCameraScreenState();
}

class _FotoProdukCameraScreenState extends State<FotoProdukCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _kamera = const [];
  int _indeks = 0;
  bool _memuat = true;
  bool _memotret = false;
  String? _pesanError;

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

  Future<void> _siapkan([int? indeks]) async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final daftar = _kamera.isEmpty ? await availableCameras() : _kamera;
      if (daftar.isEmpty) {
        throw CameraException(
          'cameraNotFound',
          'Kamera tidak ditemukan. Hubungkan webcam dan pastikan izin kamera Windows aktif.',
        );
      }
      final tujuan = indeks ??
          daftar.indexWhere(
              (kamera) => kamera.lensDirection == CameraLensDirection.back);
      final terpilih = tujuan < 0 ? 0 : tujuan % daftar.length;
      final lama = _controller;
      _controller = null;
      if (lama != null) await lama.dispose();
      final controller = CameraController(
        daftar[terpilih],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setStateIfMounted(() {
        _kamera = daftar;
        _indeks = terpilih;
        _controller = controller;
        _memuat = false;
      });
    } on Object catch (e) {
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = 'Kamera belum dapat digunakan: $e';
      });
    }
  }

  Future<void> _potret() async {
    final controller = _controller;
    if (controller == null || _memotret) return;
    setStateIfMounted(() => _memotret = true);
    try {
      final foto = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(foto);
    } on Object catch (e) {
      setStateIfMounted(() {
        _memotret = false;
        _pesanError = 'Foto belum berhasil diambil: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.judul),
        actions: [
          if (_kamera.length > 1)
            IconButton(
              tooltip: 'Ganti kamera',
              onPressed: _memuat
                  ? null
                  : () => _siapkan((_indeks + 1) % _kamera.length),
              icon: const Icon(Icons.cameraswitch_outlined),
            ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.no_photography_outlined, size: 48),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _siapkan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba lagi'),
                        ),
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
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton.icon(
                          onPressed: _memotret ? null : _potret,
                          icon: _memotret
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_outlined),
                          label: Text(
                              _memotret ? 'Mengambil foto…' : 'Ambil Foto'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
