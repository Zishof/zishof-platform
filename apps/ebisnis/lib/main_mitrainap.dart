import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian "MitraInap" -- admin hotel/penginapan (MVP LANGKAH 3).
///
/// Perintah build (KEDUA parameter wajib, konsisten -- lihat catatan
/// [AppVariant.isMitraInap]; flavor Android `mitrainap` BELUM dibuat di
/// build.gradle, jadi baru build Windows yang didukung):
/// ```
/// flutter build windows --release -t lib/main_mitrainap.dart \
///   --dart-define=EBISNIS_VARIANT=mitrainap
/// ```
Future<void> main() async {
  await bootstrap(const AppProductProfile.mitrainap());
}
