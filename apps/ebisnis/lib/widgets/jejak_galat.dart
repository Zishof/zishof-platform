import 'package:flutter/material.dart';

import '../api_client.dart';
import 'app_error_info.dart';

/// Menyimpan dua lapis kegagalan terakhir sebuah layar: kalimat yang tampil di
/// banner, dan jejak teknis yang disalin ke admin.
///
/// Dipakai sebagai `with JejakGalat` pada State mana pun yang menyimpan pesan
/// galat sebagai String. Pemanggilnya cukup mengganti `e.toString()` dengan
/// [terapkanGalat] pada posisi yang sama -- bentuk arrow maupun blok tetap
/// utuh -- lalu meneruskan [detailUntuk] ke widget penampilnya.
///
/// [detailUntuk] sengaja memasangkan detail dengan pesannya, bukan sekadar
/// menyimpan detail terakhir: sebuah layar bisa berganti menampilkan pesan
/// validasi lokal ("Member wajib dipilih") setelah sebelumnya gagal di server,
/// dan detail lama yang ikut terbawa ke pesan baru itu justru menyesatkan
/// orang yang membacanya.
mixin JejakGalat<T extends StatefulWidget> on State<T> {
  String? _pesanGalatTerakhir;
  String? _detailGalatTerakhir;

  /// Menyimpan jejak teknis kegagalan, lalu mengembalikan kalimat yang memang
  /// ditujukan kepada pengguna.
  String terapkanGalat(Object e) {
    final galat = GalatTampil.dari(e);
    _pesanGalatTerakhir = galat.pesan;
    _detailGalatTerakhir = galat.detail;
    return galat.pesan;
  }

  /// Jejak teknis milik [pesan]; null bila yang sedang tampil bukan pesan
  /// kegagalan terakhir, atau galatnya memang tidak punya lapis teknis.
  String? detailUntuk(String? pesan) =>
      pesan != null && pesan == _pesanGalatTerakhir
          ? _detailGalatTerakhir
          : null;
}

/// Info kegagalan yang siap ditampilkan.
///
/// [ApiException] sudah membawa `AppErrorInfo` hasil kontrak server (pesan,
/// solusi, dan `teknis` yang sebenarnya); mengubahnya lewat
/// `AppErrorInfo.dari(e.toString())` justru membuang semua itu dan menyisakan
/// hasil `toString`.
AppErrorInfo infoGalat(Object error, {String? aktivitas}) {
  if (error is AppErrorInfo) return error;
  if (error is ApiException) return error.info;
  return AppErrorInfo.dari(error, aktivitas: aktivitas);
}

/// Snackbar kegagalan berikut jalan menuju lapis teknisnya.
///
/// Snackbar tidak punya ruang untuk jejak teknis, dan jalur ini sebelumnya
/// hanya menampilkan `e.toString()` sehingga lapis itu hilang begitu snackbar
/// menutup. Tombol "Detail" membuka panel yang sama dengan [tampilkanKesalahan],
/// lengkap dengan tombol salin.
void snackbarGalat(BuildContext context, Object error, {String? aktivitas}) {
  final pengirim = ScaffoldMessenger.maybeOf(context);
  if (pengirim == null) return;
  final info = infoGalat(error, aktivitas: aktivitas);
  pengirim.showSnackBar(SnackBar(
    content: Text(info.pesan),
    duration: const Duration(seconds: 6),
    action: SnackBarAction(
      label: 'Detail',
      onPressed: () {
        if (!context.mounted) return;
        tampilkanKesalahan(context, info);
      },
    ),
  ));
}
