/// Konfigurasi alamat server eCanteen.
///
/// Endpoint yang dipakai adalah servlet `/Api` (bukan `/Api_eBisnis` seperti
/// aplikasi kasir) karena seluruh aksi member terdaftar di `ApiRouteRegistry`
/// dengan awalan `kantin_`. Host + context path dapat diubah pengguna lewat
/// layar Pengaturan Server; nilai di bawah hanya bawaan awal.
class AppConfig {
  AppConfig._();

  static const String namaAplikasi = 'eCanteen';
  static const String hostBawaan = 'kantinpcu.ecampus.id';
  static const String contextPathBawaan = 'petra';
  static const bool httpsBawaan = true;

  /// Nama servlet -- bagian ini TIDAK dikonfigurasi pengguna.
  static const String endpoint = 'Api';

  /// Kunci penyimpanan lokal (SharedPreferences).
  static const String kHost = 'ecanteen_host';
  static const String kContextPath = 'ecanteen_context_path';
  static const String kHttps = 'ecanteen_https';
  static const String kToken = 'ecanteen_token';
  static const String kUsername = 'ecanteen_username';
}
