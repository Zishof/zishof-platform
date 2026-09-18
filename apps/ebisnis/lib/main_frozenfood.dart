import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian "Sarimpi Jaya Frozen" -- POS khusus penjualan frozen food
/// untuk tenant sarimpijaya. Server bawaan https://sarimpijaya.ebisnis.id/ebisnis
/// (AppSetting.baseUrlHost).
///
/// Perintah build:
/// ```
/// flutter build windows --release -t lib/main_frozenfood.dart \
///   --dart-define=EBISNIS_VARIANT=frozenfood
/// ```
Future<void> main() async {
  await bootstrap(const AppProductProfile.frozenFood());
}
