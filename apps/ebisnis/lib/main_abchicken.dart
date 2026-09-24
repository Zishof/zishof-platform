import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian AB Chicken.
///
/// Build Windows:
/// `flutter build windows --release -t lib/main_abchicken.dart --dart-define=EBISNIS_VARIANT=abchicken`
///
/// Build Android:
/// `flutter build apk --release --flavor abchicken -t lib/main_abchicken.dart --dart-define=EBISNIS_VARIANT=abchicken`
Future<void> main() async {
  await bootstrap(const AppProductProfile.abChicken());
}
