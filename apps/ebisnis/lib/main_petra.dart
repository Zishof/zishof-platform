import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian "eKantin Petra" -- kantin Universitas Kristen Petra yang
/// dikelola Direktorat Pengembangan Usaha Sosial. Fiturnya sama dgn POS
/// eBisnis; yang berbeda identitas, aset, tata letak layar Masuk (dua kolom
/// mengikuti versi web), dan server bawaan kantinpcu.ecampus.id/petra
/// (AppSetting.baseUrlHost).
///
/// Perintah build (KEDUA parameter wajib, konsisten -- salah kombinasi
/// terdeteksi `cocokDenganDartDefine()` dan tercatat ke error_log):
/// ```
/// flutter build windows --release -t lib/main_petra.dart \
///   --dart-define=EBISNIS_VARIANT=petra
/// flutter build apk --release --flavor petra \
///   -t lib/main_petra.dart --dart-define=EBISNIS_VARIANT=petra
/// ```
Future<void> main() async {
  await bootstrap(const AppProductProfile.petra());
}
