import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Lima titik referensi ArcFace/SFace pada kanvas 112x112 (urutan: mata kiri,
/// mata kanan, hidung, sudut mulut kiri, sudut mulut kanan) — sama dengan
/// yang dipakai `FaceRecognizerSF.alignCrop` OpenCV, supaya embedding klien
/// sebanding dengan referensi mana pun yang di-enroll lewat pipeline SFace.
const titikReferensiSface = <Offset>[
  Offset(38.2946, 51.6963),
  Offset(73.5318, 51.5014),
  Offset(56.0252, 71.7366),
  Offset(41.5493, 92.3655),
  Offset(70.7299, 92.2041),
];

/// Ukuran kanvas masukan SFace.
const ukuranSface = 112;

/// Transformasi kesebangunan 2D (rotasi+skala+translasi):
/// `u = a*x - b*y + tx;  v = b*x + a*y + ty`.
class TransformasiSerupa {
  const TransformasiSerupa(this.a, this.b, this.tx, this.ty);

  final double a;
  final double b;
  final double tx;
  final double ty;

  Offset terapkan(Offset p) =>
      Offset(a * p.dx - b * p.dy + tx, b * p.dx + a * p.dy + ty);

  /// Kebalikannya (utk sampling warp: piksel tujuan -> koordinat sumber).
  TransformasiSerupa balik() {
    final det = a * a + b * b;
    if (det == 0) {
      throw ArgumentError('Transformasi degenerate (skala nol).');
    }
    final ia = a / det;
    final ib = -b / det;
    // inverse translation: -R^-1 * t
    final itx = -(ia * tx - ib * ty);
    final ity = -(ib * tx + ia * ty);
    return TransformasiSerupa(ia, ib, itx, ity);
  }

  /// Least-squares kesebangunan yang memetakan [sumber] -> [tujuan]
  /// (bentuk tertutup; ekuivalen Umeyama utk kasus similarity 2D).
  static TransformasiSerupa dariTitik(
      List<Offset> sumber, List<Offset> tujuan) {
    if (sumber.length != tujuan.length || sumber.length < 2) {
      throw ArgumentError('Butuh >= 2 pasangan titik dgn jumlah sama.');
    }
    final n = sumber.length;
    double sx = 0, sy = 0, ux = 0, uy = 0;
    for (var i = 0; i < n; i++) {
      sx += sumber[i].dx;
      sy += sumber[i].dy;
      ux += tujuan[i].dx;
      uy += tujuan[i].dy;
    }
    sx /= n;
    sy /= n;
    ux /= n;
    uy /= n;
    double sxx = 0, sxy = 0, norm = 0;
    for (var i = 0; i < n; i++) {
      final x = sumber[i].dx - sx;
      final y = sumber[i].dy - sy;
      final u = tujuan[i].dx - ux;
      final v = tujuan[i].dy - uy;
      sxx += x * u + y * v;
      sxy += x * v - y * u;
      norm += x * x + y * y;
    }
    if (norm == 0) {
      throw ArgumentError('Titik sumber berhimpit semua.');
    }
    final a = sxx / norm;
    final b = sxy / norm;
    final tx = ux - (a * sx - b * sy);
    final ty = uy - (b * sx + a * sy);
    return TransformasiSerupa(a, b, tx, ty);
  }
}

/// Perkiraan yaw (menoleh kiri/kanan) dari 5 landmark: posisi hidung relatif
/// terhadap titik tengah mata, dinormalkan jarak antar-mata. 0 = frontal,
/// negatif = hidung bergeser ke kiri gambar, positif = ke kanan. Ini PROXY
/// kasar utk tantangan liveness "toleh", bukan estimasi pose presisi.
double perkiraanYaw(List<Offset> landmark) {
  if (landmark.length < 3) {
    throw ArgumentError('Butuh minimal mata kiri, mata kanan, hidung.');
  }
  final mataKiri = landmark[0];
  final mataKanan = landmark[1];
  final hidung = landmark[2];
  final tengah = Offset(
      (mataKiri.dx + mataKanan.dx) / 2, (mataKiri.dy + mataKanan.dy) / 2);
  final jarakMata = (mataKanan - mataKiri).distance;
  if (jarakMata <= 0) return 0;
  return (hidung.dx - tengah.dx) / jarakMata;
}

/// Skor liveness aktif dari tantangan dua pose (frontal lalu toleh):
/// gerakan yaw harus cukup besar (bukan foto diam) DAN kedua pose harus
/// tetap orang yang sama (cosine antar-embedding pose tidak boleh anjlok —
/// menangkal trik ganti orang/ganti foto di tengah tantangan).
///
/// BUKAN anti-spoof bersertifikat — keterbatasan ini dicatat di dokumen
/// modul dan release notes.
double skorLivenessTantangan({
  required double yawFrontal,
  required double yawToleh,
  required double cosineAntarPose,
  double yawMinimal = 0.18,
  double cosineMinimal = 0.35,
}) {
  final gerak = (yawToleh - yawFrontal).abs();
  if (gerak < yawMinimal) return 0;
  if (cosineAntarPose < cosineMinimal) return 0;
  // Peta gerak [yawMinimal .. 2*yawMinimal] -> [0.6 .. 1.0], dijepit.
  final skala =
      0.6 + 0.4 * math.min(1.0, (gerak - yawMinimal) / yawMinimal);
  return double.parse(skala.toStringAsFixed(3));
}
