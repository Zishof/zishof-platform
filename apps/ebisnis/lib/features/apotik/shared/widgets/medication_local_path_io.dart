import 'dart:io';

import 'package:flutter/widgets.dart';

Widget? buildMedicationLocalPathImage({
  required String path,
  required BoxFit fit,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  final bersih = path.trim();
  if (bersih.isEmpty) return null;
  return Image.file(
    File(bersih),
    key: const ValueKey('medication-image-local-path'),
    fit: fit,
    cacheWidth: 200,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    errorBuilder: errorBuilder,
  );
}
