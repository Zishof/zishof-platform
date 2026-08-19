/// <h3>Penampung diff emisi [MasterOffline.daftarCacheDulu] utk layar daftar.</h3>
///
/// Pola baca lokal-dulu memberi DUA emisi: snapshot lokal (tampil seketika)
/// lalu hasil server berikut diff-nya. Setiap layar sebelumnya menyalin ~30
/// baris `setState` yang sama utk memindahkan diff itu ke field-nya; kelas ini
/// meringkasnya jadi satu panggilan:
///
/// ```dart
/// final _diff = DiffDaftarLokal();
/// ...
/// await MasterOffline.daftarCacheDulu(aksi, body, cacheKey, onData: (hasil) {
///   if (!mounted) return;
///   setStateIfMounted(() {
///     _daftar = _diff.terapkan(hasil);
///     _total = _diff.total ?? _daftar.length;
///     _memuat = false;
///   });
/// });
/// ```
///
/// [idBaru]/[idBerubah] dipakai `KilauBaris` utk menganimasikan baris yang
/// benar-benar baru/berubah di server (termasuk perubahan dari kasir lain),
/// [jumlahHapus] utk banner "N data dihapus di server", dan [versi] naik tiap
/// ada perubahan sehingga animasi kilau dipicu ulang.
class DiffDaftarLokal {
  Set<String> idBaru = const <String>{};
  Set<String> idBerubah = const <String>{};
  int jumlahHapus = 0;
  int versi = 0;

  /// True saat emisi terakhir berasal dari server (bukan snapshot lokal).
  bool dariServer = false;

  /// Total baris menurut server pada emisi terakhir (null bila tidak dikirim
  /// atau emisi lokal) -- layar memakainya utk paginasi.
  int? total;

  /// Ada perubahan yang layak ditandai ke user pada emisi terakhir.
  bool get adaPerubahan =>
      idBaru.isNotEmpty || idBerubah.isNotEmpty || jumlahHapus > 0;

  /// Serap satu emisi; kembalikan barisnya sbg `List<Map<String, dynamic>>`.
  List<Map<String, dynamic>> terapkan(Map<String, dynamic> hasil,
      {String fieldData = 'data'}) {
    final data = ((hasil[fieldData] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    dariServer = hasil['dariServer'] == true;
    if (dariServer) {
      idBaru = Set<String>.from(hasil['idBaru'] as Set? ?? const <String>{});
      idBerubah =
          Set<String>.from(hasil['idBerubah'] as Set? ?? const <String>{});
      jumlahHapus = (hasil['jumlahHapus'] as int?) ?? 0;
      total = (hasil['total'] as num?)?.toInt();
      if (adaPerubahan) versi++;
    } else {
      // Emisi lokal: tanpa kilau (belum ada pembanding server) dan tanpa
      // total server -- layar jatuh ke jumlah baris lokal.
      idBaru = const <String>{};
      idBerubah = const <String>{};
      jumlahHapus = 0;
      total = null;
    }
    return data;
  }

  /// Bersihkan penanda (mis. sebelum memuat halaman/filter lain).
  void reset() {
    idBaru = const <String>{};
    idBerubah = const <String>{};
    jumlahHapus = 0;
    total = null;
    dariServer = false;
  }
}
