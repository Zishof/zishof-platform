import 'bootstrap.dart';
import 'product_profile.dart';

/// Entrypoint varian "eBisnis Inventory & Sales" (PERINTAH_MASTER §4.1).
///
/// Perintah build (KEDUA parameter wajib, konsisten -- lihat catatan
/// [AppVariant.isInventorySales]):
/// ```
/// flutter build windows --release -t lib/main_inventory_sales.dart \
///   --dart-define=EBISNIS_VARIANT=inventory_sales
/// flutter build apk --release --flavor inventorySales \
///   -t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales
/// ```
Future<void> main() async {
  await bootstrap(const AppProductProfile.inventorySales());
}
