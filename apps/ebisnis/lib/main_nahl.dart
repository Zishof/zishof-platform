import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint POS Al-Bahjah An-Nahl.
///
/// Build Windows:
///   flutter build windows --release -t lib/main_nahl.dart
///     --dart-define=EBISNIS_VARIANT=nahl
/// Build Android:
///   flutter build apk --release --flavor nahl -t lib/main_nahl.dart
///     --dart-define=EBISNIS_VARIANT=nahl
Future<void> main() async {
  await bootstrap(const AppProductProfile.nahl());
}
