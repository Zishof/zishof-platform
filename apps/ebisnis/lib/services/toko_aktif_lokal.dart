import 'package:core_db/core_db.dart';

import '../api_client.dart';

/// Toko aktif per SERVER + AKUN pada perangkat ini.
/// bug "toko berubah sendiri saat pindah menu": server hanya menyimpan toko
/// aktif per AKUN (`Tbmuser.tokoAktifMultiToko`, satu kolom polos di baris
/// user), BUKAN per perangkat. Kalau akun kasir yang sama login di lebih dari
/// satu jendela/mesin sekaligus (lazim di lapangan -- satu akun "kasir1"
/// dipakai di beberapa terminal), memilih toko di SATU jendela menimpa nilai
/// itu utk SEMUA jendela lain yang login akun sama -- begitu jendela lain
/// memuat ulang konfigurasi (mis. hanya krn pindah menu memicu mount ulang
/// `KasirScreen`), toko yang ditampilkan diam-diam ikut berubah walau kasir
/// di jendela itu tidak pernah memilihnya.
///
/// Nilai di sini adalah "klaim" akun pada perangkat ini atas satu toko dari
/// `Sesi.instance.daftarToko` -- TIDAK PERNAH ditimpa otomatis oleh respons
/// server `konfigurasi` (lihat `_terapkanKonfigDenganGuardToko` di
/// `kasir_screen.dart`); hanya alur eksplisit "Pilih Toko"/"Ganti Toko" yang
/// menulisnya. Sekali perangkat ini punya klaim, redirect toko dari jendela
/// LAIN yang berbagi akun tidak akan lagi memengaruhi tampilan di sini.
class TokoAktifLokal {
  TokoAktifLokal._();
  static final TokoAktifLokal instance = TokoAktifLokal._();

  String _kunci(String userId) =>
      '${ApiClient.baseUrl.trim().toLowerCase()}|${userId.trim().toLowerCase()}';

  Future<int?> muat(String userId) async {
    return CoreDb.instance.tokoAktifAkunBaca(_kunci(userId));
  }

  Future<void> simpan(String userId, int tokoId) async {
    await CoreDb.instance.tokoAktifAkunSimpan(_kunci(userId), tokoId);
  }

  Future<void> hapus(String userId) async {
    await CoreDb.instance.tokoAktifAkunHapus(_kunci(userId));
  }
}
