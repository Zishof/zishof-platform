// Diagnostik model YuNet NYATA — headless, tanpa webcam.
//
// SENGAJA di luar folder test/ supaya tidak ikut suite default (butuh
// onnxruntime.dll pada PATH). Jalankan manual:
//   $env:PATH = "...\build\windows\x64\runner\Release;$env:PATH"
//   flutter test tool\diagnostik\face_onnx_diagnostik_test.dart
//
// Tujuan: membongkar bentuk keluaran YuNet utk berbagai ukuran masukan,
// membuktikan/menyanggah hipotesis padding kelipatan-32 (rujukan
// FaceDetectorYN OpenCV mem-pad input ke kelipatan 32 sebelum inferensi).
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ebisnis/services/face_onnx/onnx_face_provider.dart';
import 'package:ebisnis/services/face_onnx/penjalan_model_ort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bongkar panjang tensor YuNet utk beberapa ukuran masukan', () async {
    // flutter_tester menemukan onnxruntime.dll LAMA milik Windows ML di
    // System32 lebih dulu (urutan pencarian DLL); pre-load DLL bundel plugin
    // dgn path penuh supaya modul bernama sama sudah terdaftar duluan.
    // Aplikasi asli tidak butuh ini: direktori exe dicari pertama.
    DynamicLibrary.open(
        r'C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\build\windows\x64'
        r'\runner\Release\onnxruntime.dll');
    final mesin = PenjalanModelOrt(
        lokator: LokatorModelWajah(direktoriKandidat: ['assets/face']));
    await mesin.siapkan();
    // Temuan: input YuNet ONNX ini TETAP 640x640 (bukan dinamis).
    const w = 640, h = 640;
    final blob = Float32List(3 * w * h);
    final keluaran = await mesin.deteksi(blob, w, h);
    // ignore: avoid_print
    print('=== masukan ${w}x$h ===');
    for (final e in keluaran.entries) {
      // ignore: avoid_print
      print('  ${e.key}: len=${e.value.length}');
    }
    for (final stride in const [8, 16, 32]) {
      final sel = (w ~/ stride) * (h ~/ stride);
      // ignore: avoid_print
      print('  harapan stride $stride: sel=$sel bbox=${sel * 4} '
          'kps=${sel * 10}');
    }
    // Uji juga SFace: blob 112x112 nol -> embedding harus keluar.
    final emb = await mesin.embed(Float32List(3 * 112 * 112));
    // ignore: avoid_print
    print('=== SFace: dim=${emb.length}, contoh=${emb.take(4).toList()} ===');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
