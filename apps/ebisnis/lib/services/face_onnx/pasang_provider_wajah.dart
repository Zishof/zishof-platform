import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../screens/anggota/face_capture_screen.dart';
import '../face_embedding_provider.dart';
import 'onnx_face_provider.dart';
import 'penjalan_model_ort.dart';

/// Kunci navigator app UTAMA (bukan jendela Layar Pelanggan kedua) — dipakai
/// provider wajah utk membuka layar kamera dari luar pohon widget pemanggil.
final GlobalKey<NavigatorState> kunciNavigatorUtama =
    GlobalKey<NavigatorState>();

/// Pasang provider wajah on-device (YuNet + SFace via ONNX Runtime).
/// Idempoten; dipanggil dari initState EBisnisApp. Tanpa berkas model atau
/// runtime yang gagal dimuat, `ready()` provider false dan seluruh jalur
/// wajah tetap fail-closed — TIDAK pernah memalsukan kesiapan.
void pasangProviderWajahOnDevice() {
  if (FaceOnDeviceCapture.provider != null) return;
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  FaceOnDeviceCapture.pasang(OnnxFaceEmbeddingProvider(
    mesin: PenjalanModelOrt(lokator: LokatorModelWajah.bawaan()),
    ambilFoto: () async {
      final context = kunciNavigatorUtama.currentContext;
      if (context == null || !context.mounted) return null;
      return FaceCaptureScreen.ambil(context);
    },
  ));
}
