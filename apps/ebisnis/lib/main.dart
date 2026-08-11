import 'bootstrap.dart';
import 'product_profile.dart';

// Ekspor ulang utk pemakai lama entrypoint ini (widget_test.dart memakai
// `EBisnisApp` lewat import main.dart) -- isi aplikasi pindah ke bootstrap.dart
// saat refactor varian (PERINTAH_MASTER §4.1), kontrak import lama dipertahankan.
export 'bootstrap.dart' show EBisnisApp;

/// Entrypoint varian POS existing -- melayani eBisnis default DAN Al-Bahjah
/// (dibedakan `--dart-define=EBISNIS_VARIANT`, lihat [AppProductProfile
/// .dariDartDefine]). Varian "eBisnis Inventory & Sales" memakai entrypoint
/// terpisah `main_inventory_sales.dart`.
Future<void> main() async {
  await bootstrap(AppProductProfile.dariDartDefine());
}
