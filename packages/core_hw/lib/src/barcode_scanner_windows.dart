import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

Future<String?> pindaiBarcodeWindows(
  BuildContext context, {
  required String judul,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => _PemindaiBarcodeWindows(judul: judul),
    ),
  );
}

class _PemindaiBarcodeWindows extends StatefulWidget {
  const _PemindaiBarcodeWindows({required this.judul});

  final String judul;

  @override
  State<_PemindaiBarcodeWindows> createState() =>
      _PemindaiBarcodeWindowsState();
}

class _PemindaiBarcodeWindowsState extends State<_PemindaiBarcodeWindows> {
  final DecodeParams _decodeParams = DecodeParams(
    tryHarder: true,
    tryRotate: true,
    tryInverted: true,
    maxSize: 1600,
  );

  List<CameraDescription> _kamera = const <CameraDescription>[];
  CameraDescription? _kameraAktif;
  CameraController? _controller;
  bool _memuat = true;
  bool _memindai = false;
  bool _selesai = false;
  String? _pesanError;
  String _status = 'Menyiapkan webcam...';

  @override
  void initState() {
    super.initState();
    unawaited(_siapkanKamera());
  }

  @override
  void dispose() {
    _selesai = true;
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _siapkanKamera([CameraDescription? pilihan]) async {
    setState(() {
      _memuat = true;
      _pesanError = null;
      _status = 'Mencari webcam...';
    });
    try {
      final daftar = _kamera.isEmpty ? await availableCameras() : _kamera;
      if (daftar.isEmpty) {
        throw CameraException(
          'cameraNotFound',
          'Webcam tidak ditemukan. Hubungkan webcam lalu tekan Coba lagi.',
        );
      }
      final terpilih = pilihan ?? daftar.first;
      final lama = _controller;
      _controller = null;
      if (lama != null) await lama.dispose();

      final controller = CameraController(
        terpilih,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || _selesai) {
        await controller.dispose();
        return;
      }
      setState(() {
        _kamera = daftar;
        _kameraAktif = terpilih;
        _controller = controller;
        _memuat = false;
        _status = 'Arahkan barcode atau QR-Code ke kotak pemindaian.';
      });
      unawaited(_loopPindai());
    } on Object catch (error) {
      if (!mounted || _selesai) return;
      setState(() {
        _memuat = false;
        _pesanError = _pesanKamera(error);
        _status = 'Webcam belum siap.';
      });
    }
  }

  String _pesanKamera(Object error) {
    if (error is CameraException) {
      if (error.code == 'CameraAccessDenied') {
        return 'Akses webcam ditolak. Izinkan akses kamera di Settings > '
            'Privacy & security > Camera, lalu coba lagi.';
      }
      return error.description ??
          'Webcam tidak dapat digunakan (${error.code}).';
    }
    return 'Webcam tidak dapat digunakan: $error';
  }

  Future<void> _loopPindai() async {
    if (_memindai || _selesai) return;
    _memindai = true;
    try {
      while (mounted && !_selesai && _controller?.value.isInitialized == true) {
        await _pindaiSatuFrame();
        if (!_selesai) {
          await Future<void>.delayed(const Duration(milliseconds: 650));
        }
      }
    } finally {
      _memindai = false;
    }
  }

  Future<void> _pindaiSatuFrame() async {
    final controller = _controller;
    if (controller == null || controller.value.isTakingPicture || _selesai) {
      return;
    }

    XFile? gambar;
    try {
      gambar = await controller.takePicture();
      final hasil = await zx.readBarcodeImagePathString(
        gambar.path,
        _decodeParams,
      );
      final nilai = hasil.text?.trim();
      if (hasil.isValid && nilai != null && nilai.isNotEmpty && mounted) {
        _selesai = true;
        Navigator.of(context).pop(nilai);
      }
    } on CameraException catch (error) {
      if (!mounted || _selesai) return;
      setState(() {
        _pesanError = _pesanKamera(error);
        _status = 'Pemindaian berhenti.';
      });
      _selesai = true;
    } finally {
      final path = gambar?.path;
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } on Object {
          // Snapshot kamera bersifat sementara; kegagalan hapus tidak boleh
          // menggagalkan hasil pemindaian.
        }
      }
    }
  }

  Future<void> _gantiKamera(CameraDescription? kamera) async {
    if (kamera == null || kamera == _kameraAktif) return;
    _selesai = true;
    await _controller?.dispose();
    _controller = null;
    _selesai = false;
    await _siapkanKamera(kamera);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.judul),
        actions: <Widget>[
          if (_kamera.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CameraDescription>(
                  value: _kameraAktif,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  items: _kamera
                      .map(
                        (kamera) => DropdownMenuItem<CameraDescription>(
                          value: kamera,
                          child: SizedBox(
                            width: 220,
                            child: Text(
                              kamera.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _gantiKamera,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (controller?.value.isInitialized == true)
            Center(
              child: AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: CameraPreview(controller),
              ),
            )
          else
            const ColoredBox(color: Colors.black),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 520,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Colors.black54, blurRadius: 18),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 28,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_memuat) const LinearProgressIndicator(),
                    if (_memuat) const SizedBox(height: 12),
                    Text(
                      _pesanError ?? _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _pesanError == null
                            ? Colors.white
                            : Colors.red.shade200,
                        fontSize: 16,
                      ),
                    ),
                    if (_pesanError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          _selesai = false;
                          unawaited(_siapkanKamera(_kameraAktif));
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba lagi'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
