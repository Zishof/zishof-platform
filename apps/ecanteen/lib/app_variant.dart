/// Varian build eCanteen.
///
/// Satu basis kode, beberapa identitas. Pembeda dipilih saat build lewat
/// `--dart-define=ECANTEEN_VARIANT=<kode>` (sisi Dart) dan `--flavor <kode>`
/// (label peluncur Android). KEDUANYA wajib dan harus konsisten -- salah
/// kombinasi membuat nama di dalam aplikasi berbeda dgn nama di peluncur.
///
/// ```
/// flutter build apk --release --flavor petra \
///   --dart-define=ECANTEEN_VARIANT=petra
/// flutter build windows --release --dart-define=ECANTEEN_VARIANT=petra
/// ```
class AppVariant {
  AppVariant._();

  static const kode = String.fromEnvironment(
    'ECANTEEN_VARIANT',
    defaultValue: 'umum',
  );

  /// Varian kantin Universitas Kristen Petra, dikelola Direktorat
  /// Pengembangan Usaha Sosial. Nama yang tampil adalah nama direktorat,
  /// bukan nama produk.
  static const isPetra = kode == 'petra';

  /// Nama yang dilihat pengguna: judul jendela, layar Masuk, dan label
  /// peluncur Android (lewat resValue app_name pada flavor).
  static const namaAplikasi =
      isPetra ? 'Direktorat Pengembangan Usaha Sosial' : 'eCanteen';

  /// Nama pendek untuk tempat yang sempit (bilah judul ponsel, installer).
  static const namaPendek = isPetra ? 'eKantin Petra' : 'eCanteen';

  /// Namespace penyimpanan lokal. Sengaja TIDAK mengikuti nama tampilan
  /// supaya perubahan branding tidak pernah memutus sesi/preferensi yang
  /// sudah tersimpan di perangkat.
  static const namespacePenyimpanan = isPetra ? 'ecanteen_petra' : 'ecanteen';

  /// Server bawaan per varian. Pengguna tetap dapat menggantinya lewat
  /// layar Alamat Server.
  static const hostBawaan =
      isPetra ? 'kantinpcu.ecampus.id' : 'kantinpcu.ecampus.id';
  static const contextPathBawaan = isPetra ? 'petra' : 'petra';
  static const httpsBawaan = true;
}
