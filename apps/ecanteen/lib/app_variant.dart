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
  ///
  /// SATU nilai untuk semua varian: keduanya memakai applicationId yang sama
  /// (com.ecanteen.zishof, paket terdaftar di Google Play) sehingga menempati
  /// slot pemasangan yang sama. Kalau namespace-nya dipisah, mengganti build
  /// umum <-> petra akan membuat pengguna keluar sesi tanpa alasan yang
  /// terlihat.
  static const namespacePenyimpanan = 'ecanteen';

  /// Logo yang tampil di layar Masuk. Varian umum memakai ikon aplikasi.
  static const logoAsset = isPetra
      ? 'assets/images/petra/icon.png'
      : 'assets/icon/ecanteen-icon.png';

  /// ── Identitas panel kiri layar Masuk ──────────────────────────────────
  /// Disamakan dgn POS Desktop varian yang sama supaya petugas dan anggota
  /// melihat identitas yang persis sama.
  static const judulLogin = isPetra ? 'Masuk eKantin' : namaAplikasi;
  static const subJudulLogin = isPetra
      ? 'Selamat datang kembali, silakan masuk ke akun Anda.'
      : 'Masuk dengan akun member Anda';
  static const namaOrganisasiLogin =
      isPetra ? 'Direktorat Pengembangan Usaha Sosial' : namaAplikasi;
  static const alamatKontakLogin = isPetra
      ? 'Gedung Entrance Hall (EH), Lantai 2. UNIVERSITAS KRISTEN PETRA'
      : '';
  static const teleponKontakLogin = isPetra ? '+62-881-2526-094' : '';
  static const emailKontakLogin = isPetra ? 'office-dpus@petra.ac.id' : '';
  static const hakCiptaLogin =
      isPetra ? '© 2026 Direktorat Pengembangan Usaha Sosial' : '';

  /// Tata letak Masuk dua kolom (panel identitas + formulir).
  static const loginDuaKolom = isPetra;

  /// Server bawaan per varian. Pengguna tetap dapat menggantinya lewat
  /// layar Alamat Server.
  static const hostBawaan =
      isPetra ? 'kantinpcu.ecampus.id' : 'kantinpcu.ecampus.id';
  static const contextPathBawaan = isPetra ? 'petra' : 'petra';
  static const httpsBawaan = true;
}
