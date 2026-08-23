import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Kompresi gambar produk ke bawah [maksLampiranGambarBytes] (spesifikasi
/// user: "di bawah 500 Kb", masukannya maksimal 5 MB) sebelum diunggah -- server (`KantinHelper.produkFotoUpload`)
/// TIDAK melakukan kompresi apa pun, klien WAJIB mengirim berkas yang sudah
/// kecil. Fungsi murni/sinkron -- pemanggil (`produk_screen.dart`) menjalankan
/// ini lewat `compute()` di isolate terpisah krn decode+encode JPEG foto
/// kamera resolusi tinggi bisa berat & menjank UI kalau dijalankan langsung
/// di main isolate.
Uint8List kompresGambarKeBawah500Kb(Uint8List asal) {
  // SENGAJA tanpa [tolakBilaGambarTerlaluBesar]: foto produk dari kamera
  // dibebaskan dari pagar 5 MB. Ponsel 12 MP menghasilkan JPEG 3-6 MB secara
  // rutin, jadi pagar itu akan menolak foto yang sepenuhnya sah -- sementara
  // foto produk memang SELALU dikecilkan ke bawah 500 KB sebelum dikirim,
  // sehingga ukuran masukannya tidak pernah sampai ke server.
  //
  // Pagar 5 MB tetap berlaku untuk LAMPIRAN, yang angkanya menyamai batas
  // server dan yang berkasnya boleh bukan gambar.
  return kompresGambar(asal, maksBytes: maksLampiranGambarBytes);
}

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

// ===========================================================================
// GERBANG LAMPIRAN GAMBAR
// ===========================================================================

/// Ambang tunggal untuk SELURUH lampiran gambar di aplikasi ini.
///
/// Satu tempat, bukan angka yang diulang di tiap layar — ambang yang tersebar
/// akan berbeda-beda begitu ada yang lupa mengubah salah satunya.
const int maksLampiranGambarBytes = 500 * 1024;

/// Ambang untuk lampiran **dokumen** — faktur vendor, bukti bayar, berkas
/// pengajuan SOP.
///
/// Sengaja berbeda dari [maksLampiranGambarBytes]. Foto produk dipakai sebagai
/// katalog, jadi 500 KB memadai. Dokumen dibaca ANGKANYA — nomor faktur dan
/// nominal — dan kerugian mutunya PERMANEN: berkas dikecilkan di perangkat
/// sebelum dikirim, sehingga tidak ada salinan asli di mana pun, sementara
/// faktur itu dapat diunduh kembali dari daftar Terima Tagihan Vendor untuk
/// diperiksa. Angka 2 MB masih jauh di bawah pagar 5 MB milik server
/// (`MAKS_BYTE_LAMPIRAN`), jadi hanya klien yang perlu tahu soal ambang ini.
const int maksLampiranDokumenBytes = 2 * 1024 * 1024;

/// Batas **masukan** untuk gambar, sebelum dikecilkan.
///
/// Berbeda peran dengan [maksLampiranGambarBytes]: yang itu batas KIRIMAN
/// (hasil akhir setelah dikecilkan), yang ini batas apa yang boleh diterima
/// sejak awal. Tanpa batas atas, berkas puluhan megabita tetap didekode penuh
/// lebih dulu — berat, dan pada perangkat kasir bermemori kecil bisa mematikan
/// aplikasi sebelum sempat mengecilkannya.
///
/// Angkanya sengaja sama dengan `MAKS_BYTE_LAMPIRAN` di
/// `PengadaanPosApiHelper` sisi server, supaya klien dan server tidak punya dua
/// pendapat tentang berkas yang sama.
const int maksGambarAsalBytes = 5 * 1024 * 1024;

/// Menolak gambar yang melebihi [maksGambarAsalBytes].
///
/// Pesannya menyebut ukuran sebenarnya, bukan sekadar "terlalu besar" —
/// pengguna perlu tahu seberapa jauh selisihnya untuk memutuskan langkah
/// berikutnya.
void tolakBilaGambarTerlaluBesar(Uint8List asal) {
  if (asal.length <= maksGambarAsalBytes) return;
  final mb = (asal.length / (1024 * 1024)).toStringAsFixed(1);
  const batas = maksGambarAsalBytes ~/ (1024 * 1024);
  throw FormatException(
      'Gambar berukuran $mb MB, melebihi batas $batas MB. '
      'Perkecil atau potret ulang dengan resolusi lebih rendah.');
}

/// Tanda pengenal format gambar yang dikenali, dibaca dari byte awal berkas.
///
/// Diperiksa dari **isinya**, bukan dari ekstensi namanya. Berkas bernama
/// `.jpg` yang isinya PDF akan lolos pemeriksaan ekstensi dan baru gagal jauh
/// di hilir — atau lebih buruk, tersimpan sebagai gambar yang tidak pernah
/// dapat ditampilkan.
bool tampaknyaGambar(Uint8List b) {
  if (b.length < 12) return false;
  // JPEG: FF D8 FF
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 &&
      b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) {
    return true;
  }
  // GIF: "GIF8"
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return true;
  // BMP: "BM"
  if (b[0] == 0x42 && b[1] == 0x4D) return true;
  // WEBP: "RIFF" .... "WEBP"
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return true;
  }
  return false;
}

/// Siapkan lampiran yang **wajib** berupa gambar.
///
/// Melempar [FormatException] bila bukan gambar, dan mengecilkannya ke bawah
/// [maksLampiranGambarBytes] bila kebesaran. Gambar yang sudah cukup kecil
/// dikembalikan **apa adanya** — mengubahnya menjadi JPEG akan membuang
/// transparansi PNG tanpa memberi manfaat apa pun.
///
/// Fungsi top-level dan murni supaya dapat dijalankan lewat `compute()`:
/// decode+encode foto kamera resolusi tinggi berat dan akan menjank UI bila
/// berjalan di isolate utama.
Uint8List siapkanLampiranGambar(Uint8List asal) =>
    _siapkanGambar(asal, maksLampiranGambarBytes);

/// Sama dengan [siapkanLampiranGambar], tetapi memakai ambang DOKUMEN.
///
/// Fungsi terpisah (bukan parameter) karena pemanggilnya menjalankan ini lewat
/// `compute()`, yang hanya menerima fungsi top-level bersatu argumen.
Uint8List siapkanLampiranDokumenGambar(Uint8List asal) =>
    _siapkanGambar(asal, maksLampiranDokumenBytes);

Uint8List _siapkanGambar(Uint8List asal, int maksBytes) {
  if (!tampaknyaGambar(asal)) {
    throw const FormatException(
        'Lampiran harus berupa gambar (JPG, PNG, GIF, BMP, atau WEBP).');
  }
  tolakBilaGambarTerlaluBesar(asal);
  if (asal.length <= maksBytes) {
    // Tetap didekode untuk memastikan isinya benar-benar utuh: tanda pengenal
    // yang benar tidak menjamin badan berkasnya tidak rusak.
    if (img.decodeImage(asal) == null) {
      throw const FormatException('Berkas gambar rusak dan tidak dapat dibaca.');
    }
    return asal;
  }
  return kompresGambar(asal, maksBytes: maksBytes);
}

/// Siapkan lampiran yang **boleh** bukan gambar — faktur PDF, misalnya.
///
/// Gambar dikecilkan ke bawah ambang; yang bukan gambar dilewatkan apa adanya.
/// Dipakai pada lampiran serba-guna, sedangkan medan yang memang menuntut
/// gambar memakai [siapkanLampiranGambar].
Uint8List siapkanLampiranCampuran(Uint8List asal) =>
    _siapkanCampuran(asal, maksLampiranGambarBytes);

/// Sama dengan [siapkanLampiranCampuran], tetapi memakai ambang DOKUMEN.
Uint8List siapkanLampiranDokumenCampuran(Uint8List asal) =>
    _siapkanCampuran(asal, maksLampiranDokumenBytes);

Uint8List _siapkanCampuran(Uint8List asal, int maksBytes) {
  if (!tampaknyaGambar(asal)) {
    return asal;
  }
  tolakBilaGambarTerlaluBesar(asal);
  if (asal.length <= maksBytes) {
    return asal;
  }
  return kompresGambar(asal, maksBytes: maksBytes);
}
