import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

import 'geometri_wajah.dart';

/// Blob NCHW float32 ber-urutan kanal BGR, nilai 0..255 tanpa normalisasi —
/// mengikuti `blobFromImage(scale=1, mean=0, swapRB=false)` yang dipakai
/// referensi OpenCV utk YuNet maupun SFace.
Float32List blobBgrNchw(img.Image sumber) {
  final w = sumber.width;
  final h = sumber.height;
  final blob = Float32List(3 * w * h);
  final luas = w * h;
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = sumber.getPixel(x, y);
      blob[i] = p.b.toDouble(); // kanal B
      blob[luas + i] = p.g.toDouble(); // kanal G
      blob[2 * luas + i] = p.r.toDouble(); // kanal R
      i++;
    }
  }
  return blob;
}

/// Hasil penyusutan gambar utk detektor: gambar terskala + faktor utk
/// memetakan koordinat deteksi kembali ke gambar asli.
class GambarDeteksi {
  const GambarDeteksi(this.gambar, this.faktor);

  final img.Image gambar;

  /// koordinatAsli = koordinatDeteksi * faktor.
  final double faktor;
}

/// Ukuran masukan TETAP YuNet ONNX opencv_zoo 2023mar (dibuktikan
/// tool/diagnostik: model menolak dimensi lain).
const sisiYunet = 640;

/// Letterbox ke kanvas [sisi]x[sisi]: skalakan agar muat (aspek terjaga),
/// tempel di pojok kiri-atas kanvas hitam. Padding hanya di kanan/bawah
/// sehingga koordinat deteksi cukup dikali [GambarDeteksi.faktor] utk
/// kembali ke gambar asli.
GambarDeteksi letterboxUntukDeteksi(img.Image sumber, {int sisi = sisiYunet}) {
  final skala = sisi / math.max(sumber.width, sumber.height);
  final w = math.max(1, (sumber.width * skala).round());
  final h = math.max(1, (sumber.height * skala).round());
  final kecil = img.copyResize(sumber,
      width: w, height: h, interpolation: img.Interpolation.linear);
  final kanvas = img.Image(width: sisi, height: sisi);
  img.compositeImage(kanvas, kecil);
  return GambarDeteksi(kanvas, sumber.width / w);
}

/// Align-crop 112x112 ala `FaceRecognizerSF.alignCrop`: transformasi
/// kesebangunan 5-landmark -> [titikReferensiSface], sampling bilinear
/// balik dari gambar sumber.
img.Image potongSejajarSface(img.Image sumber, List<Offset> landmark) {
  if (landmark.length != 5) {
    throw ArgumentError('Alignment SFace butuh tepat 5 landmark.');
  }
  final maju = TransformasiSerupa.dariTitik(landmark, titikReferensiSface);
  final balik = maju.balik();
  final hasil = img.Image(width: ukuranSface, height: ukuranSface);
  for (var y = 0; y < ukuranSface; y++) {
    for (var x = 0; x < ukuranSface; x++) {
      final s = balik.terapkan(Offset(x.toDouble(), y.toDouble()));
      final piksel = _sampelBilinear(sumber, s.dx, s.dy);
      hasil.setPixelRgb(x, y, piksel[0], piksel[1], piksel[2]);
    }
  }
  return hasil;
}

List<int> _sampelBilinear(img.Image sumber, double x, double y) {
  if (x < 0 || y < 0 || x > sumber.width - 1 || y > sumber.height - 1) {
    return const [0, 0, 0];
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, sumber.width - 1);
  final y1 = math.min(y0 + 1, sumber.height - 1);
  final fx = x - x0;
  final fy = y - y0;
  final p00 = sumber.getPixel(x0, y0);
  final p10 = sumber.getPixel(x1, y0);
  final p01 = sumber.getPixel(x0, y1);
  final p11 = sumber.getPixel(x1, y1);
  int campur(num a, num b, num c, num d) => ((a * (1 - fx) * (1 - fy) +
              b * fx * (1 - fy) +
              c * (1 - fx) * fy +
              d * fx * fy))
          .round()
          .clamp(0, 255);
  return [
    campur(p00.r, p10.r, p01.r, p11.r),
    campur(p00.g, p10.g, p01.g, p11.g),
    campur(p00.b, p10.b, p01.b, p11.b),
  ];
}

/// Embedding float -> bytes float32 little-endian (kontrak
/// `FACE_EMBEDDING_F32_LE_V1` yang dibaca matcher server).
Uint8List embeddingKeBytesLe(List<double> embedding) {
  final data = ByteData(embedding.length * 4);
  for (var i = 0; i < embedding.length; i++) {
    data.setFloat32(i * 4, embedding[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Cosine similarity — dipakai memeriksa konsistensi identitas antar-pose
/// pada tantangan liveness (rumusnya sama dgn matcher server).
double cosine(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) {
    throw ArgumentError('Dimensi embedding tidak sama.');
  }
  double dot = 0, na = 0, nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
