import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian "eBisnis POS Apotik" (eFarmasi, JALAN 1: backend Java
/// AIS + modul SIRS -- lihat perintah awal POS Apotik & eMedik).
///
/// Perintah build (KEDUA parameter wajib, konsisten -- salah kombinasi
/// terdeteksi `cocokDenganDartDefine()` dan tercatat ke error_log):
/// ```
/// flutter build windows --release -t lib/main_apotik.dart \
///   --dart-define=EBISNIS_VARIANT=apotik
/// flutter build apk --release --flavor apotik \
///   -t lib/main_apotik.dart --dart-define=EBISNIS_VARIANT=apotik
/// ```
/// Flavor `apotik` memakai applicationId `id.zishof.ebisnis.apotik`, sehingga
/// dapat dipasang berdampingan dengan varian eBisnis lain pada satu perangkat.
Future<void> main() async {
  await bootstrap(const AppProductProfile.apotik());
}
