import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Kompresi gambar produk ke bawah [maksBytes] (spesifikasi user: "di bawah
/// 500 Kb") sebelum diunggah -- server (`KantinHelper.produkFotoUpload`)
/// TIDAK melakukan kompresi apa pun, klien WAJIB mengirim berkas yang sudah
/// kecil. Fungsi murni/sinkron -- pemanggil (`produk_screen.dart`) menjalankan
/// ini lewat `compute()` di isolate terpisah krn decode+encode JPEG foto
/// kamera resolusi tinggi bisa berat & menjank UI kalau dijalankan langsung
/// di main isolate.
Uint8List kompresGambarKeBawah500Kb(Uint8List asal) =>
    kompresGambar(asal, maksBytes: 500 * 1024);

/// Versi umum [kompresGambarKeBawah500Kb] dgn batas ukuran bisa diatur --
/// dipisah supaya gampang diuji dgn ambang berbeda tanpa mengubah nama fungsi
/// yang dipanggil `compute()` (compute butuh referensi fungsi top-level).
Uint8List kompresGambar(Uint8List asal, {required int maksBytes}) {
  final img.Image? terdekode = img.decodeImage(asal);
  if (terdekode == null) {
    throw const FormatException('Berkas bukan gambar yang bisa dibaca.');
  }
  // Variabel NON-nullable terpisah: promosi null-check pada variabel `Image?`
  // hilang di dalam loop yang meng-assign ulang variabel itu (flow analysis
  // Dart), bikin error compile "cannot be accessed on 'Image?'".
  img.Image gambar = terdekode;

  // Downscale dulu kalau dimensinya sangat besar -- foto kamera modern bisa
  // 4000x3000px+, jauh melebihi kebutuhan tampilan galeri/carousel POS ini.
  const maksDimensiAwal = 1600;
  if (gambar.width > maksDimensiAwal || gambar.height > maksDimensiAwal) {
    gambar = gambar.width >= gambar.height
        ? img.copyResize(gambar, width: maksDimensiAwal)
        : img.copyResize(gambar, height: maksDimensiAwal);
  }

  int kualitas = 90;
  Uint8List hasil =
      Uint8List.fromList(img.encodeJpg(gambar, quality: kualitas));

  // Turunkan kualitas dulu (biaya kualitas visual < biaya kecilkan dimensi).
  while (hasil.length > maksBytes && kualitas > 30) {
    kualitas -= 10;
    hasil = Uint8List.fromList(img.encodeJpg(gambar, quality: kualitas));
  }

  // Kalau di kualitas terendah MASIH kebesaran (foto sangat detail/kompleks),
  // kecilkan lagi dimensinya bertahap sampai lolos ambang atau mentok kecil.
  int dimensiSekarang = gambar.width >= gambar.height ? gambar.width : gambar.height;
  while (hasil.length > maksBytes && dimensiSekarang > 400) {
    dimensiSekarang = (dimensiSekarang * 0.8).round();
    gambar = gambar.width >= gambar.height
        ? img.copyResize(gambar, width: dimensiSekarang)
        : img.copyResize(gambar, height: dimensiSekarang);
    hasil = Uint8List.fromList(img.encodeJpg(gambar, quality: 60));
  }

  return hasil;
}
