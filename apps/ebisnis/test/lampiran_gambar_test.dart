import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:ebisnis/services/kompresi_gambar.dart';

/// Penjaga gerbang lampiran gambar.
///
/// Aturan pengguna: gambar disimpan sebagai blob supaya persisten, maksimum
/// 500 KB, dan yang lebih besar dikecilkan otomatis di POS Desktop/Android.
/// Lampiran yang memang harus gambar wajib ditolak bila bukan gambar.
void main() {
  /// Foto yang sengaja dibuat besar dan berisik supaya JPEG tidak dapat
  /// memampatkannya dengan mudah — foto rata warna akan lolos 500 KB tanpa
  /// membuktikan apa pun.
  Uint8List fotoBesar({int sisi = 1100}) {
    // Derau ditulis lewat buffer mentah, bukan setPixelRgb per piksel: satu
    // juta panggilan metode di VM Dart membuat uji ini berjalan menit-menitan.
    final g = img.Image(width: sisi, height: sisi, numChannels: 3);
    final buf = g.toUint8List();
    var benih = 12345;
    for (var i = 0; i < buf.length; i++) {
      benih = (benih * 1103515245 + 12345) & 0x7FFFFFFF;
      buf[i] = (benih >> 16) & 0xFF;
    }
    return Uint8List.fromList(img.encodeJpg(g, quality: 100));
  }

  Uint8List pngKecil() {
    final g = img.Image(width: 8, height: 8);
    img.fill(g, color: img.ColorRgb8(10, 200, 30));
    return Uint8List.fromList(img.encodePng(g));
  }

  /// Gambar yang MELEBIHI batas masukan 5 MB.
  ///
  /// Dibuat dari derau dengan kualitas maksimum: gambar rata warna sebesar apa
  /// pun akan menyusut jauh di bawah 5 MB saat dikodekan, sehingga tidak dapat
  /// menguji pagarnya sama sekali.
  Uint8List fotoLewatBatas() {
    var sisi = 3000;
    while (sisi < 12000) {
      final g = img.Image(width: sisi, height: sisi, numChannels: 3);
      final buf = g.toUint8List();
      var benih = 987654321;
      for (var i = 0; i < buf.length; i++) {
        benih = (benih * 1103515245 + 12345) & 0x7FFFFFFF;
        buf[i] = (benih >> 16) & 0xFF;
      }
      final b = Uint8List.fromList(img.encodeJpg(g, quality: 100));
      if (b.length > maksGambarAsalBytes) return b;
      sisi = (sisi * 1.5).round();
    }
    throw StateError('gagal membuat contoh di atas 5 MB');
  }

  test('batas masukan 5 MB sama dengan batas lampiran di server', () {
    expect(maksGambarAsalBytes, 5 * 1024 * 1024,
        reason: 'MAKS_BYTE_LAMPIRAN di PengadaanPosApiHelper juga 5 MB; dua '
            'pendapat berbeda tentang berkas yang sama akan menyesatkan');
    expect(maksGambarAsalBytes, greaterThan(maksLampiranGambarBytes),
        reason: 'batas masukan harus lebih longgar daripada batas kiriman, '
            'kalau tidak tidak ada yang bisa dikecilkan');
  });

  test('gambar di atas 5 MB DITOLAK, bukan dikecilkan diam-diam', () {
    final asal = fotoLewatBatas();
    expect(asal.length, greaterThan(maksGambarAsalBytes));

    expect(() => siapkanLampiranGambar(asal), throwsFormatException);
    expect(() => siapkanLampiranCampuran(asal), throwsFormatException);
    expect(() => kompresGambarKeBawah500Kb(asal), throwsFormatException);
  });

  test('pesan penolakan menyebut ukuran sebenarnya, bukan sekadar besar', () {
    final asal = fotoLewatBatas();
    try {
      siapkanLampiranGambar(asal);
      fail('seharusnya ditolak');
    } on FormatException catch (e) {
      expect(e.message, contains('MB'),
          reason: 'pengguna perlu tahu seberapa jauh selisihnya');
      expect(e.message, contains('5 MB'));
    }
  });

  test('gambar TEPAT di batas 5 MB masih diterima', () {
    // Batasnya inklusif: yang ditolak adalah yang MELEBIHI, bukan yang sama.
    final pas = Uint8List(maksGambarAsalBytes);
    expect(() => tolakBilaGambarTerlaluBesar(pas), returnsNormally);
    final lewat = Uint8List(maksGambarAsalBytes + 1);
    expect(() => tolakBilaGambarTerlaluBesar(lewat), throwsFormatException);
  });

  test('ambangnya tepat 500 KB, satu tempat untuk seluruh aplikasi', () {
    expect(maksLampiranGambarBytes, 500 * 1024);
  });

  test('gambar besar dikecilkan ke bawah 500 KB', () {
    final asal = fotoBesar();
    expect(asal.length, greaterThan(maksLampiranGambarBytes),
        reason: 'contoh ujinya harus benar-benar melebihi ambang, kalau tidak '
            'uji ini tidak membuktikan apa pun');

    final hasil = siapkanLampiranGambar(asal);
    expect(hasil.length, lessThanOrEqualTo(maksLampiranGambarBytes));
    expect(img.decodeImage(hasil), isNotNull,
        reason: 'hasilnya harus tetap gambar yang dapat dibaca');
  });

  test('gambar yang sudah kecil dikembalikan APA ADANYA', () {
    final png = pngKecil();
    expect(png.length, lessThan(maksLampiranGambarBytes));

    final hasil = siapkanLampiranGambar(png);
    expect(identical(hasil, png) || hasil.length == png.length, isTrue,
        reason: 'mengubahnya menjadi JPEG akan membuang transparansi PNG '
            'tanpa memberi manfaat apa pun');
    expect(tampaknyaGambar(hasil), isTrue);
  });

  test('yang bukan gambar DITOLAK pada lampiran wajib-gambar', () {
    final pdf = Uint8List.fromList('%PDF-1.7\n%bukan gambar sama sekali'.codeUnits);
    expect(() => siapkanLampiranGambar(pdf), throwsA(isA<FormatException>()));

    final teks = Uint8List.fromList('sekadar teks biasa yang panjang'.codeUnits);
    expect(() => siapkanLampiranGambar(teks), throwsA(isA<FormatException>()));

    final kosong = Uint8List(0);
    expect(() => siapkanLampiranGambar(kosong), throwsA(isA<FormatException>()));
  });

  test('nama berkas berbohong tidak menolong: yang diperiksa ISI-nya', () {
    // Persis kasus yang dicegah: berkas bernama foto.jpg tetapi isinya PDF.
    // Penyaring ekstensi FilePicker meloloskannya; gerbang ini tidak.
    final pdfMenyamar =
        Uint8List.fromList('%PDF-1.4 berpura-pura menjadi foto.jpg'.codeUnits);
    expect(tampaknyaGambar(pdfMenyamar), isFalse);
    expect(() => siapkanLampiranGambar(pdfMenyamar),
        throwsA(isA<FormatException>()));
  });

  test('gambar rusak ditolak walau tanda pengenalnya benar', () {
    // Diawali tanda JPEG, tetapi badannya sampah.
    final rusak = Uint8List.fromList(
        <int>[0xFF, 0xD8, 0xFF] + List<int>.filled(200, 0x41));
    expect(tampaknyaGambar(rusak), isTrue,
        reason: 'tanda pengenalnya memang JPEG');
    expect(() => siapkanLampiranGambar(rusak), throwsA(isA<FormatException>()),
        reason: 'tanda pengenal yang benar TIDAK menjamin badan berkas utuh');
  });

  test('lampiran campuran: gambar dikecilkan, non-gambar dilewatkan', () {
    final pdf = Uint8List.fromList('%PDF-1.7 faktur asli'.codeUnits);
    expect(siapkanLampiranCampuran(pdf), same(pdf),
        reason: 'PDF faktur harus lewat utuh, bukan ditolak');

    final besar = fotoBesar();
    final hasil = siapkanLampiranCampuran(besar);
    expect(hasil.length, lessThanOrEqualTo(maksLampiranGambarBytes));
  });

  test('tanda pengenal seluruh format yang didukung dikenali', () {
    expect(tampaknyaGambar(pngKecil()), isTrue, reason: 'PNG');
    expect(
        tampaknyaGambar(Uint8List.fromList(
            img.encodeJpg(img.Image(width: 4, height: 4), quality: 80))),
        isTrue,
        reason: 'JPEG');
    expect(tampaknyaGambar(Uint8List.fromList('GIF89a'.codeUnits + List<int>.filled(20, 0))),
        isTrue,
        reason: 'GIF');
    expect(tampaknyaGambar(Uint8List.fromList('BM'.codeUnits + List<int>.filled(20, 0))),
        isTrue,
        reason: 'BMP');
    expect(
        tampaknyaGambar(Uint8List.fromList(
            'RIFF'.codeUnits + <int>[0, 0, 0, 0] + 'WEBP'.codeUnits + List<int>.filled(8, 0))),
        isTrue,
        reason: 'WEBP');

    expect(tampaknyaGambar(Uint8List.fromList(List<int>.filled(4, 0))), isFalse,
        reason: 'berkas terlalu pendek tidak boleh dianggap gambar');
  });
}
