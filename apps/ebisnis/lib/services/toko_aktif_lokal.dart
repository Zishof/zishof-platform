import 'package:shared_preferences/shared_preferences.dart';

/// Toko aktif utk PERANGKAT/INSTALASI INI SAJA (bukan akun) -- gap-closure
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
/// Nilai di sini adalah "klaim" perangkat ini atas satu toko dari
/// `Sesi.instance.daftarToko` -- TIDAK PERNAH ditimpa otomatis oleh respons
/// server `konfigurasi` (lihat `_terapkanKonfigDenganGuardToko` di
/// `kasir_screen.dart`); hanya alur eksplisit "Pilih Toko"/"Ganti Toko" yang
/// menulisnya. Sekali perangkat ini punya klaim, redirect toko dari jendela
/// LAIN yang berbagi akun tidak akan lagi memengaruhi tampilan di sini.
class TokoAktifLokal {
  TokoAktifLokal._();
  static final TokoAktifLokal instance = TokoAktifLokal._();

  static const _kunciTokoId = 'toko_aktif_lokal_id';

  Future<int?> muat() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kunciTokoId);
  }

  Future<void> simpan(int tokoId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kunciTokoId, tokoId);
  }

  Future<void> hapus() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kunciTokoId);
  }
}
