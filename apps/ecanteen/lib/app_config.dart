import 'app_variant.dart';

/// Konfigurasi alamat server eCanteen.
///
/// Endpoint yang dipakai adalah servlet `/Api` (bukan `/Api_eBisnis` seperti
/// aplikasi kasir) karena seluruh aksi member terdaftar di `ApiRouteRegistry`
/// dengan awalan `kantin_`. Host + context path dapat diubah pengguna lewat
/// layar Alamat Server; nilai bawaan berasal dari varian build.
class AppConfig {
  AppConfig._();

  static const String namaAplikasi = AppVariant.namaAplikasi;
  static const String namaPendek = AppVariant.namaPendek;
  static const String hostBawaan = AppVariant.hostBawaan;
  static const String contextPathBawaan = AppVariant.contextPathBawaan;
  static const bool httpsBawaan = AppVariant.httpsBawaan;

  /// Nama servlet -- bagian ini TIDAK dikonfigurasi pengguna.
  static const String endpoint = 'Api';

  /// Kunci penyimpanan lokal (SharedPreferences), diberi awalan namespace
  /// varian supaya dua varian pada satu perangkat tidak saling menimpa.
  static const String _ns = AppVariant.namespacePenyimpanan;
  static const String kHost = '${_ns}_host';
  static const String kContextPath = '${_ns}_context_path';
  static const String kHttps = '${_ns}_https';
  static const String kToken = '${_ns}_token';
  static const String kUsername = '${_ns}_username';
}
