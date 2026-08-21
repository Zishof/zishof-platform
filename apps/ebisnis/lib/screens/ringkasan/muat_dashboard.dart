import 'dart:convert';

import 'package:core_db/core_db.dart';

import '../../api_client.dart';

/// Pemuat data satu tab Dashboard dengan SALINAN LOKAL sebagai penyangga.
///
/// <b>Mengapa ada.</b> Dashboard sepenuhnya bergantung pada server: begitu
/// jawabannya tidak dapat diproses -- entah karena jaringan mati, gateway
/// membalas 502, atau alamatnya dialihkan sehingga badan jawabannya bukan JSON
/// -- seluruh isi tab hilang dan hanya menyisakan kotak galat. Padahal data
/// yang baru saja tampil beberapa menit sebelumnya masih jauh lebih berguna
/// daripada layar kosong, terutama bagi pemilik toko yang sekadar ingin melihat
/// angka terakhir.
///
/// <b>Cara kerja.</b> Salinan terakhir ditampilkan LEBIH DAHULU bila ada,
/// sehingga tab langsung terisi tanpa menunggu jaringan. Setelah jawaban server
/// tiba, isinya ditimpa dengan angka terbaru dan salinannya diperbarui.
///
/// <b>Kapan galat tetap ditampilkan.</b> Hanya bila TIDAK ada salinan yang bisa
/// ditampilkan. Selama ada salinan, kegagalan apa pun cukup diwakili penanda
/// "data tersimpan" beserta waktunya -- pengguna tetap melihat angka, dan tahu
/// angka itu bukan yang terkini. Ini SENGAJA tidak dibatasi pada galat offline
/// saja: server yang menjawab dengan sesuatu yang tidak dapat diproses sama
/// tidak bergunanya dengan server yang tidak menjawab.
Future<void> muatTabDashboard({
  required String aksi,
  required Map<String, dynamic> payload,

  /// Dipanggil setiap kali ada data untuk ditampilkan. [dariCache] menyalakan
  /// penanda "data tersimpan"; [disimpanPada] waktu salinan itu dibuat.
  required void Function(
          Map<String, dynamic> data, bool dariCache, DateTime? disimpanPada)
      onData,

  /// Dipanggil HANYA bila tidak ada satu pun data yang dapat ditampilkan.
  /// Galatnya diserahkan mentah supaya pemanggil dapat memakai
  /// `terapkanGalat` miliknya sendiri (metode mixin, bukan fungsi bebas).
  required void Function(Object galat) onError,

  /// Dipanggil bila widget-nya masih terpasang; pemanggil memakai `mounted`.
  required bool Function() masihAktif,
}) async {
  // Kunci diturunkan dari aksi + payload supaya salinan otomatis terpisah per
  // filter (tanggal acuan, toko, dan seterusnya). Tab tidak perlu memikirkan
  // kuncinya sendiri, dan tidak mungkin keliru memakai kunci yang sama untuk
  // dua rentang tanggal berbeda.
  final kunciCache = 'dashboard:$aksi:${jsonEncode(payload)}';
  var adaSalinan = false;

  final tersimpan = await CoreDb.instance.ambilCacheReferensi(kunciCache);
  if (tersimpan != null && masihAktif()) {
    try {
      final lokal = jsonDecode(tersimpan) as Map<String, dynamic>;
      adaSalinan = true;
      onData(lokal, true,
          DateTime.tryParse('${lokal['_disimpanPada'] ?? ''}'));
    } catch (_) {
      // Salinan rusak -- perlakukan seolah tidak ada, lalu lanjut ke server.
      adaSalinan = false;
    }
  }

  try {
    final hasil = await ApiClient.instance.aksi(aksi, payload);
    if (!masihAktif()) return;
    onData(hasil, false, null);
    // Stempel waktu disimpan DI DALAM amplop supaya pemuatan berikutnya dapat
    // memberi tahu KAPAN salinan ini dibuat. Kunci berawalan garis bawah tidak
    // pernah dibaca perender tab (semuanya membaca kunci spesifik).
    await CoreDb.instance.simpanCacheReferensi(
        kunciCache,
        jsonEncode({
          ...hasil,
          '_disimpanPada': DateTime.now().toIso8601String(),
        }));
  } catch (e) {
    if (!masihAktif()) return;
    if (!adaSalinan) onError(e);
  }
}
