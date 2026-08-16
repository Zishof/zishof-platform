import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian "eBisnis POS eMedik" -- SATU build memuat POS Apotik
/// sekaligus kasir layanan medis; perbedaan hak per pengguna diatur Tbmrole
/// server (seed LANGKAH 1.5), bukan binary terpisah. Server bawaan
/// ebisnis.id/ebisnis (AppSetting.baseUrlHost).
///
/// Perintah build (KEDUA parameter wajib, konsisten -- salah kombinasi
/// terdeteksi `cocokDenganDartDefine()` dan tercatat ke error_log):
/// ```
/// flutter build windows --release -t lib/main_emedik.dart \
///   --dart-define=EBISNIS_VARIANT=emedik
/// flutter build apk --release --flavor emedik \
///   -t lib/main_emedik.dart --dart-define=EBISNIS_VARIANT=emedik
/// ```
Future<void> main() async {
  await bootstrap(const AppProductProfile.emedik());
}
