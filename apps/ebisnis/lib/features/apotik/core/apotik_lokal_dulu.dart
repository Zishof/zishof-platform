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
