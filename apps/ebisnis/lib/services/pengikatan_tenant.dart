import 'package:core_auth/core_auth.dart';
import 'package:core_db/core_db.dart';

import '../api_client.dart';

/// Keputusan yang dihasilkan [PengikatanTenant.periksa].
enum KeputusanPengikatan {
  /// Perangkat sudah terikat pada tenant yang sama, atau baru saja diikat.
  /// Jalan terus.
  lanjut,

  /// Pengguna tidak bernaung pada tenant mana pun -- akun legacy atau admin
  /// pusat. Jalan terus pada schema existing, persis seperti sebelum ada
  /// multi-tenant. Ini keadaan SELURUH pengguna hari ini.
  tanpaTenant,

  /// Pengguna punya lebih dari satu tenant dan harus memilih. Klien belum
  /// punya pemilihnya, jadi keadaan ini ditampilkan apa adanya alih-alih
  /// menebak salah satu.
  pilihTenant,

  /// Perangkat terikat pada tenant LAIN dan antreannya masih berisi.
  /// **Jangan** lanjutkan: kirim dulu antreannya dari akun tenant lama.
  tertahanAntrean,

  /// Perangkat terikat pada tenant lain, antreannya kosong, dan data lokalnya
  /// sudah diarsipkan lalu diikat ulang. Aman dilanjutkan dengan cache kosong.
  dialihkan,
}

/// Hasil pemeriksaan, lengkap dengan bahan untuk pesan ke pengguna.
class HasilPengikatan {
  const HasilPengikatan(
    this.keputusan, {
    this.antreanTertunda = 0,
    this.tenantLamaId,
    this.tenantAktifId,
    this.arsip,
  });

  final KeputusanPengikatan keputusan;

  /// Jumlah pekerjaan yang belum terkirim; hanya berarti pada
  /// [KeputusanPengikatan.tertahanAntrean].
  final int antreanTertunda;

  /// Tenant yang sebelumnya memiliki data pada perangkat ini.
  final int? tenantLamaId;

  /// Jalur berkas basis data lama yang diarsipkan, bila ada.
  final String? arsip;

  /// Tenant yang akhirnya aktif pada perangkat ini, atau {@code null} bila
  /// jalurnya schema existing. Dipakai pemanggil untuk menyetel
  /// `ApiClient.simpanTenantId`.
  final int? tenantAktifId;

  bool get bolehLanjut =>
      keputusan != KeputusanPengikatan.tertahanAntrean &&
      keputusan != KeputusanPengikatan.pilihTenant;
}

/// Menjaga agar satu perangkat hanya memuat data satu tenant.
///
/// Keputusan 23 Agustus 2026: **satu perangkat melayani satu tenant, satu
/// tenant boleh memakai banyak perangkat.** Karena itu tidak ada perpindahan
/// tenant saat aplikasi berjalan, dan `CoreDb.configureStorage` yang menolak
/// perubahan namespace sesudah basis data terbuka justru menjadi penjaganya.
///
/// Yang tetap harus dijaga adalah perangkat yang **dialihkan**: pegawai pindah
/// cabang, perangkat dipakai ulang, atau seseorang salah login. Tanpa
/// penjagaan, tiga hal buruk terjadi sekaligus:
///
/// 1. antrean milik tenant lama terkirim memakai token tenant baru;
/// 2. cache produk/pelanggan tenant lama tampil sebagai data tenant baru;
/// 3. kata sandi luring tenant lama masih menerima login.
///
/// Ketiganya ditutup di sini.
///
/// **Antrean lebih dulu, selalu.** Bila masih ada pekerjaan yang belum
/// terkirim, pengalihan **ditolak** — bukan dilanjutkan dengan membuang
/// antreannya. Pekerjaan kasir yang belum sampai ke server adalah uang yang
/// belum tercatat; pemiliknya harus mengirimkannya lebih dulu dari akun lama.
class PengikatanTenant {
  const PengikatanTenant._();

  /// Periksa dan, bila perlu, alihkan perangkat ke tenant yang sedang login.
  ///
  /// Panggil **sesudah** login berhasil dan tenant aktif diketahui, tetapi
  /// **sebelum** cache dimuat atau penyiram antrean dinyalakan.
  static Future<HasilPengikatan> periksa({
    required int tenantId,
    String? tenantKode,
    String? serverSidik,
    String? akunSidik,
  }) async {
    final db = CoreDb.instance;
    final status = await db.periksaPengikatan(tenantId);

    if (status == StatusPengikatan.cocok) {
      return HasilPengikatan(KeputusanPengikatan.lanjut, tenantAktifId: tenantId);
    }

    if (status == StatusPengikatan.belumTerikat) {
      // Pemasangan baru, atau basis data lama yang naik dari versi sebelum v13.
      //
      // Basis data lama TIDAK diadopsi diam-diam sebagai milik tenant ini bila
      // masih menyimpan pekerjaan: isinya bisa saja milik pemasangan lain
      // (§15.4 melarang menebak). Yang kosong aman diikat.
      final tertunda = await db.hitungAntreanTertunda();
      if (tertunda > 0) {
        return HasilPengikatan(
          KeputusanPengikatan.tertahanAntrean,
          antreanTertunda: tertunda,
        );
      }
      await db.ikatTenant(
        tenantId: tenantId,
        tenantKode: tenantKode,
        serverSidik: serverSidik,
        akunSidik: akunSidik,
      );
      return HasilPengikatan(KeputusanPengikatan.lanjut, tenantAktifId: tenantId);
    }

    // status == beda: perangkat memuat data tenant LAIN.
    final lama = await db.pengikatanSekarang();
    final tenantLamaId = lama == null ? null : lama['tenant_id'] as int?;

    final tertunda = await db.hitungAntreanTertunda();
    if (tertunda > 0) {
      return HasilPengikatan(
        KeputusanPengikatan.tertahanAntrean,
        antreanTertunda: tertunda,
        tenantLamaId: tenantLamaId,
      );
    }

    // Urutannya penting. Kredensial luring dibuang LEBIH DULU: bila pengarsipan
    // gagal di tengah jalan, yang tertinggal adalah perangkat tanpa jalan masuk
    // luring — bukan perangkat yang masih menerima kata sandi tenant lama.
    await VerifikatorSandiLokal.instance.hapus();
    final arsip = await db.lepaskanDanArsipkan();
    await db.ikatTenant(
      tenantId: tenantId,
      tenantKode: tenantKode,
      serverSidik: serverSidik,
      akunSidik: akunSidik,
    );
    return HasilPengikatan(
      KeputusanPengikatan.dialihkan,
      tenantLamaId: tenantLamaId,
      tenantAktifId: tenantId,
      arsip: arsip,
    );
  }

  /// Tanyakan tenant aktif ke server, lalu jalankan [periksa].
  ///
  /// Dipanggil **sesudah** token tersimpan (aksinya butuh autentikasi) tetapi
  /// **sebelum** bukti kata sandi luring disimpan dan sebelum cache dimuat.
  /// Urutan itu penting: bila pengikatan ditolak, perangkat tidak boleh
  /// meninggalkan jejak identitas baru sama sekali.
  ///
  /// Pengguna tanpa tenant -- akun legacy dan admin pusat, yaitu semua orang
  /// hari ini -- ditolak server dengan `TENANT_ACCESS_DENIED`. Itu **bukan**
  /// kegagalan login: jalurnya memang schema existing.
  static Future<HasilPengikatan> periksaSetelahLogin() async {
    Map<String, dynamic> data;
    try {
      final hasil = await ApiClient.instance.aksi('tenant_context', const {});
      final d = hasil['data'];
      if (d is! Map) {
        return const HasilPengikatan(KeputusanPengikatan.tanpaTenant);
      }
      data = Map<String, dynamic>.from(d);
    } on ApiException catch (e) {
      switch (e.kode) {
        case 'TENANT_ACCESS_DENIED':
          // Tidak bernaung pada tenant mana pun -> jalur existing.
          return const HasilPengikatan(KeputusanPengikatan.tanpaTenant);
        case 'TENANT_SELECTION_REQUIRED':
          return const HasilPengikatan(KeputusanPengikatan.pilihTenant);
        default:
          // Aksi tenant_context belum ada di server lama, atau tenant sedang
          // suspended/belum siap. Keduanya TIDAK boleh menggagalkan login POS
          // yang selama ini berjalan; jalur existing tetap terbuka.
          return const HasilPengikatan(KeputusanPengikatan.tanpaTenant);
      }
    } catch (_) {
      return const HasilPengikatan(KeputusanPengikatan.tanpaTenant);
    }

    final tenantId = data['tenant_id'];
    if (tenantId is! int || tenantId <= 0) {
      return const HasilPengikatan(KeputusanPengikatan.tanpaTenant);
    }
    return periksa(
      tenantId: tenantId,
      tenantKode: data['tenant_code'] as String?,
    );
  }

  /// Pesan siap tampil untuk keadaan yang menahan pengguna.
  static String pesan(HasilPengikatan hasil) {
    switch (hasil.keputusan) {
      case KeputusanPengikatan.pilihTenant:
        return 'Akun Anda terdaftar pada lebih dari satu usaha. Versi aplikasi '
            'ini belum dapat memilihnya. Hubungi admin untuk menentukan usaha '
            'mana yang dipakai pada perangkat ini.';
      case KeputusanPengikatan.tanpaTenant:
        return '';
      case KeputusanPengikatan.tertahanAntrean:
        return 'Perangkat ini masih menyimpan ${hasil.antreanTertunda} data '
            'yang belum terkirim ke server. Masuk kembali dengan akun '
            'sebelumnya dan tunggu sampai semuanya terkirim, baru perangkat '
            'ini dapat dipakai untuk usaha lain.';
      case KeputusanPengikatan.dialihkan:
        return 'Perangkat ini sebelumnya dipakai untuk usaha lain. Data lokal '
            'lama sudah diarsipkan dan aplikasi memulai dengan data kosong.';
      case KeputusanPengikatan.lanjut:
        return '';
    }
  }
}
