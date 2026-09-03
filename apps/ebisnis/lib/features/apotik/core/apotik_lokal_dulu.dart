/// <h3>Kontrak "lokal dulu" untuk layar master apotik.</h3>
///
/// Dipisah dari layarnya supaya beberapa halaman memakai bentuk yang sama dan
/// dapat disuntik pada test — jalur UI yang diuji persis jalur produksi, bukan
/// cabang khusus test.
///
/// **Yang SENGAJA tidak lewat jalur ini** (dan alasannya, supaya tidak
/// "dirapikan" oleh orang berikutnya):
///
/// * `apotik_bayar` — penjualan menuntut server mengalokasikan lot FEFO,
///   menolak lot kedaluwarsa/ditahan, dan menulis register obat terkendali.
///   Mengantre penjualan saat offline berarti obat bisa terlanjur diserahkan
///   dari lot yang seharusnya ditolak, dan registernya baru terbentuk
///   belakangan. Kegagalan JARINGAN saat membayar ditangani terpisah lewat
///   `ApotikPembayaranTertundaStore` (status `paidUnsynced`), bukan dengan
///   berpura-pura transaksinya sukses.
/// * `apotik_terima_barang` — penerimaan menambah stok dan membuat lot baru,
///   tetapi aksinya belum punya kunci idempoten. Kiriman ulang akan
///   menggandakan stok, dan stok hantu di apotek berujung pada obat yang
///   dikira ada padahal tidak.
/// * `apotik_sesi_kas_tutup` — angka tutup kas dihitung server dari catatan
///   pembayaran; menutup sesi secara offline hanya akan membekukan angka yang
///   belum lengkap.
/// * Laporan, metrik, dan rekonsiliasi — semuanya agregat sisi server.
///   Menampilkan uang dari cache lebih berbahaya daripada mengatakan "belum
///   terbaca".
/// * `apotik_resep_detail` — rincian satu resep dibaca tepat sebelum obat
///   disiapkan; yang berubah di sini (baris sudah ditebus atau belum) justru
///   yang menentukan boleh-tidaknya menyerahkan obat. DAFTAR antreannya
///   lokal-dulu, rinciannya tidak.
/// * `apotik_item_batch` — daftar lot untuk memilih batch FEFO. Status lot
///   (karantina, recall, kedaluwarsa) justru yang paling sering berubah dan
///   paling berbahaya bila basi: memilih dari daftar lama berarti menyiapkan
///   obat dari lot yang mungkin sudah ditahan. Selagi pembayaran memang
///   menuntut server, daftar lot pun dibaca langsung.
library;

import 'package:flutter/widgets.dart';

/// Pemuat daftar "lokal dulu": emisi pertama dari cache
/// (`dariServer: false`), emisi berikutnya dari server beserta diff
/// `idBaru`/`idBerubah`/`jumlahHapus` untuk animasi.
///
/// Bentuknya sengaja sama persis dengan `MasterOffline.daftarCacheDulu`
/// sehingga implementasi produksinya cukup ditunjuk langsung.
typedef MuatDaftarApotik = Future<void> Function(
  String aksi,
  Map<String, dynamic> body,
  String cacheKey, {
  required void Function(Map<String, dynamic> hasil) onData,
});

/// Penyimpan master ber-antrean (offline-first) dengan indikator animatif.
/// Bentuknya sama dengan `prosesSimpanMaster`.
typedef SimpanMasterApotik = Future<Map<String, dynamic>> Function(
  BuildContext context, {
  required String aksi,
  required Map<String, dynamic> body,
  String? kunci,
  String? cacheKey,
  Map<String, dynamic>? rowLokal,
});

/// Kunci cache master obat — dipakai bersama layar persediaan lama supaya
/// keduanya melihat snapshot yang sama.
const String kunciCacheItemApotik = 'master:apotik_item';

/// Kunci cache monitor batch/kedaluwarsa.
const String kunciCacheBatchApotik = 'master:apotik_batch';

/// Kunci cache antrean resep. Dipisah per filter "hanya menunggu" karena
/// keduanya daftar yang berbeda; menyatukannya akan membuat isi cache
/// berganti-ganti dan diff-nya berisik.
String kunciCacheResepApotik({required bool hanyaMenunggu}) =>
    hanyaMenunggu ? 'master:apotik_resep_menunggu' : 'master:apotik_resep';

/// Kunci cache daftar metode pembayaran (master, jarang berubah).
const String kunciCacheCaraBayarApotik = 'master:apotik_cara_bayar';

/// Menyaring hasil dari CACHE menurut kata kunci.
///
/// Cache master hanya menyimpan hasil kueri terakhir. Tanpa penyaringan ini,
/// mengetik kata kunci baru saat server tak terjangkau akan menampilkan hasil
/// pencarian SEBELUMNYA seolah-olah itu jawabannya — obat yang salah muncul
/// karena alasan yang tidak terlihat pengguna. Emisi dari server tidak perlu
/// disaring: server sudah menyaringnya.
List<Map<String, dynamic>> saringCacheLokal(
    List<Map<String, dynamic>> data, String keyword) {
  final k = keyword.trim().toLowerCase();
  if (k.isEmpty) return data;
  return data.where((e) {
    for (final kolom in const ['nama', 'kode', 'barcode', 'kandungan']) {
      if ('${e[kolom] ?? ''}'.toLowerCase().contains(k)) return true;
    }
    return false;
  }).toList();
}
