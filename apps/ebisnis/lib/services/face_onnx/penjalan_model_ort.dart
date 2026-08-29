import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../biometric_capture_bridge.dart';
import 'onnx_face_provider.dart';

/// Implementasi [MesinInferensiWajah] di atas ONNX Runtime (plugin
/// `onnxruntime`). SATU-SATUNYA berkas yang menyentuh runtime native —
/// logika pipeline lain murni Dart supaya teruji tanpa DLL/AAR.
///
/// Nama tensor masukan/keluaran dibaca dari sesi (bukan hardcode) sehingga
/// pembaruan minor model dari OpenCV Zoo tidak mematahkan pemetaan.
class PenjalanModelOrt implements MesinInferensiWajah {
  PenjalanModelOrt({required this.lokator});

  final LokatorModelWajah lokator;

  OrtSession? _yunet;
  OrtSession? _sface;

  @override
  Future<void> siapkan() async {
    if (_yunet != null && _sface != null) return;
    // bacaBytes: filesystem dulu (override Desktop), lalu asset bundle
    // (jalur distribusi Android -- model ikut APK).
    final bytesYunet = await lokator.bacaBytes(LokatorModelWajah.namaYunet);
    final bytesSface = await lokator.bacaBytes(LokatorModelWajah.namaSface);
    if (bytesYunet == null || bytesSface == null) {
      throw const PosBiometricUnavailable(
          'Berkas model wajah belum ada. Jalankan '
          'tool/unduh_model_wajah.ps1 (verifikasi SHA-256 otomatis).');
    }
    try {
      OrtEnv.instance.init();
      final opsi = OrtSessionOptions();
      // fromBuffer, BUKAN fromFile: fromFile pada Windows meneruskan path
      // dgn encoding sempit padahal ORT mengharapkan wide-char, sehingga
      // path terbaca sbg UTF-16 acak dan model tidak pernah termuat
      // (ditemukan lewat tool/diagnostik saat UAT webcam 2026-08-29).
      _yunet ??= OrtSession.fromBuffer(bytesYunet, opsi);
      _sface ??= OrtSession.fromBuffer(bytesSface, opsi);
    } on Object catch (e) {
      _yunet = null;
      _sface = null;
      throw PosBiometricUnavailable(
          'Runtime ONNX tidak dapat memuat model wajah: $e');
    }
  }

  @override
  Future<Map<String, List<double>>> deteksi(
      Float32List blob, int lebar, int tinggi) async {
    await siapkan();
    final sesi = _yunet!;
    return _jalankan(sesi, blob, [1, 3, tinggi, lebar]);
  }

  @override
  Future<List<double>> embed(Float32List blob) async {
    await siapkan();
    final sesi = _sface!;
    final keluaran = await _jalankan(sesi, blob, [1, 3, 112, 112]);
    if (keluaran.isEmpty) {
      throw const PosBiometricUnavailable('SFace tidak mengeluarkan tensor.');
    }
    return keluaran.values.first;
  }

  Future<Map<String, List<double>>> _jalankan(
      OrtSession sesi, Float32List blob, List<int> bentuk) async {
    OrtValueTensor? masukan;
    OrtRunOptions? runOpsi;
    List<OrtValue?>? hasil;
    try {
      masukan = OrtValueTensor.createTensorWithDataList(blob, bentuk);
      runOpsi = OrtRunOptions();
      hasil = sesi.run(runOpsi, {sesi.inputNames.first: masukan});
      final peta = <String, List<double>>{};
      for (var i = 0; i < hasil.length; i++) {
        final nilai = hasil[i];
        if (nilai is! OrtValueTensor) continue;
        final nama = i < sesi.outputNames.length
            ? sesi.outputNames[i]
            : 'keluaran_$i';
        peta[nama] = _ratakan(nilai.value);
      }
      return peta;
    } on PosBiometricUnavailable {
      rethrow;
    } on Object catch (e) {
      throw PosBiometricUnavailable('Inferensi model wajah gagal: $e');
    } finally {
      masukan?.release();
      runOpsi?.release();
      if (hasil != null) {
        for (final v in hasil) {
          v?.release();
        }
      }
    }
  }

  static List<double> _ratakan(Object? nilai) {
    final keluar = <double>[];
    void telusuri(Object? v) {
      if (v is num) {
        keluar.add(v.toDouble());
      } else if (v is List) {
        for (final e in v) {
          telusuri(e);
        }
      } else if (v is Float32List) {
        keluar.addAll(v);
      }
    }

    telusuri(nilai);
    return keluar;
  }
}
