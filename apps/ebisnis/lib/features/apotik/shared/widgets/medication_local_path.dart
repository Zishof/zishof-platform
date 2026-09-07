import 'package:flutter/widgets.dart';

import 'medication_local_path_stub.dart'
    if (dart.library.io) 'medication_local_path_io.dart' as implementation;

/// Membuat gambar dari path lokal hanya pada platform yang mempunyai
/// filesystem. Web mengembalikan null dan melanjutkan ke URL/fallback.
Widget? buildMedicationLocalPathImage({
  required String path,
  required BoxFit fit,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) =>
    implementation.buildMedicationLocalPathImage(
      path: path,
      fit: fit,
      errorBuilder: errorBuilder,
    );
