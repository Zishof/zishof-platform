import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Satu wajah hasil YuNet: skor gabungan, kotak, dan 5 landmark
/// (mata kiri, mata kanan, hidung, mulut kiri, mulut kanan) dalam koordinat
/// piksel gambar masukan detektor.
class DeteksiWajah {
  const DeteksiWajah(this.skor, this.kotak, this.landmark);

  final double skor;
  final Rect kotak;
  final List<Offset> landmark;
}

/// Decoder keluaran YuNet 2023mar (`face_detection_yunet_2023mar.onnx`),
/// mengikuti referensi `FaceDetectorYN` OpenCV: tiga skala (stride 8/16/32),
/// tiap sel mengeluarkan cls, obj, bbox (dx,dy,logW,logH), dan 5 pasang kps.
///
/// skor = sqrt(clamp(cls) * clamp(obj));
/// cx = (kolom + dx) * stride; cy = (baris + dy) * stride;
/// w = exp(logW) * stride;     h = exp(logH) * stride;
/// kps_x = (kolom + kx) * stride; kps_y = (baris + ky) * stride.
List<DeteksiWajah> decodeYuNet({
  required Map<String, List<double>> keluaran,
  required int lebarInput,
  required int tinggiInput,
  double ambangSkor = 0.7,
  double ambangNms = 0.3,
}) {
  final kandidat = <DeteksiWajah>[];
  for (final stride in const [8, 16, 32]) {
    final cls = keluaran['cls_$stride'];
    final obj = keluaran['obj_$stride'];
    final bbox = keluaran['bbox_$stride'];
    final kps = keluaran['kps_$stride'];
    if (cls == null || obj == null || bbox == null || kps == null) {
      throw ArgumentError('Keluaran YuNet stride $stride tidak lengkap.');
    }
    final kolom = (lebarInput / stride).ceil();
    final baris = (tinggiInput / stride).ceil();
    final jumlahSel = kolom * baris;
    if (cls.length < jumlahSel ||
        obj.length < jumlahSel ||
        bbox.length < jumlahSel * 4 ||
        kps.length < jumlahSel * 10) {
      throw ArgumentError(
          'Ukuran tensor YuNet stride $stride tidak cocok dgn input '
          '${lebarInput}x$tinggiInput.');
    }
    for (var i = 0; i < jumlahSel; i++) {
      final skor = math.sqrt(
          cls[i].clamp(0.0, 1.0) * obj[i].clamp(0.0, 1.0));
      if (skor < ambangSkor) continue;
      final c = i % kolom;
      final r = i ~/ kolom;
      final cx = (c + bbox[i * 4]) * stride;
      final cy = (r + bbox[i * 4 + 1]) * stride;
      final w = math.exp(bbox[i * 4 + 2]) * stride;
      final h = math.exp(bbox[i * 4 + 3]) * stride;
      final landmark = List<Offset>.generate(
          5,
          (k) => Offset((c + kps[i * 10 + k * 2]) * stride,
              (r + kps[i * 10 + k * 2 + 1]) * stride));
      kandidat.add(DeteksiWajah(
          skor,
          Rect.fromCenter(
              center: Offset(cx, cy), width: w, height: h),
          landmark));
    }
  }
  return _nms(kandidat, ambangNms);
}

double _iou(Rect a, Rect b) {
  final irisan = a.intersect(b);
  if (irisan.width <= 0 || irisan.height <= 0) return 0;
  final luasIrisan = irisan.width * irisan.height;
  final gabungan =
      a.width * a.height + b.width * b.height - luasIrisan;
  return gabungan <= 0 ? 0 : luasIrisan / gabungan;
}

List<DeteksiWajah> _nms(List<DeteksiWajah> kandidat, double ambang) {
  final urut = List<DeteksiWajah>.from(kandidat)
    ..sort((x, y) => y.skor.compareTo(x.skor));
  final hasil = <DeteksiWajah>[];
  for (final d in urut) {
    if (hasil.every((h) => _iou(h.kotak, d.kotak) < ambang)) {
      hasil.add(d);
    }
  }
  return hasil;
}
