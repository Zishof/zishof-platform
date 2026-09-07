import 'medication_image.dart';

/// Alias kompatibilitas bagi layar Apotik yang masih memakai nama lama.
@Deprecated('Gunakan MedicationImage untuk implementasi baru.')
class MedicationThumbnail extends MedicationImage {
  const MedicationThumbnail({
    super.key,
    required super.item,
    super.width,
    super.height,
  });
}
