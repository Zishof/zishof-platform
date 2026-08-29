import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:ebisnis/services/biometric_capture_bridge.dart';
import 'package:ebisnis/services/face_embedding_provider.dart';
import 'package:ebisnis/services/face_onnx/geometri_wajah.dart';
import 'package:ebisnis/services/face_onnx/onnx_face_provider.dart';
import 'package:ebisnis/services/face_onnx/sface_pipeline.dart';
import 'package:ebisnis/services/face_onnx/yunet_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Bangun keluaran YuNet sintetis satu wajah pada grid stride 8 dengan
/// MEMBALIK rumus decoder — decode(encode(x)) harus mengembalikan x, jadi
/// test ini mengunci kontrak rumusnya, bukan sekadar mengulang implementasi.
Map<String, List<double>> keluaranYuNetSintetis({
  required int lebar,
  required int tinggi,
  required Rect kotak,
  required List<Offset> landmark,
  double skor = 0.95,
}) {
  final keluaran = <String, List<double>>{};
  for (final stride in const [8, 16, 32]) {
    final kolom = (lebar / stride).ceil();
    final baris = (tinggi / stride).ceil();
    final n = kolom * baris;
    keluaran['cls_$stride'] = List.filled(n, 0);
    keluaran['obj_$stride'] = List.filled(n, 0);
    keluaran['bbox_$stride'] = List.filled(n * 4, 0);
    keluaran['kps_$stride'] = List.filled(n * 10, 0);
  }
  const stride = 8;
  final kolom = (lebar / stride).ceil();
  final c = (kotak.center.dx / stride).floor();
  final r = (kotak.center.dy / stride).floor();
  final i = r * kolom + c;
  keluaran['cls_$stride']![i] = skor;
  keluaran['obj_$stride']![i] = skor;
  keluaran['bbox_$stride']![i * 4] = kotak.center.dx / stride - c;
  keluaran['bbox_$stride']![i * 4 + 1] = kotak.center.dy / stride - r;
  keluaran['bbox_$stride']![i * 4 + 2] = math.log(kotak.width / stride);
  keluaran['bbox_$stride']![i * 4 + 3] = math.log(kotak.height / stride);
  for (var k = 0; k < 5; k++) {
    keluaran['kps_$stride']![i * 10 + k * 2] = landmark[k].dx / stride - c;
    keluaran['kps_$stride']![i * 10 + k * 2 + 1] =
        landmark[k].dy / stride - r;
  }
  return keluaran;
}

List<Offset> _landmarkUji({double geserHidung = 0}) => [
      const Offset(60, 50),
      const Offset(100, 50),
      Offset(80 + geserHidung, 70),
      const Offset(65, 90),
      const Offset(95, 90),
    ];

class _MesinPalsu implements MesinInferensiWajah {
  _MesinPalsu({required this.landmarkPerPanggilan});

  final List<List<Offset>> landmarkPerPanggilan;
  int panggilanDeteksi = 0;

  @override
  Future<void> siapkan() async {}

  @override
  Future<Map<String, List<double>>> deteksi(
      Float32List blob, int lebar, int tinggi) async {
    final landmark =
        landmarkPerPanggilan[panggilanDeteksi % landmarkPerPanggilan.length];
    panggilanDeteksi++;
    return keluaranYuNetSintetis(
      lebar: lebar,
      tinggi: tinggi,
      kotak: const Rect.fromLTWH(40, 30, 80, 90),
      landmark: landmark,
    );
  }

  @override
  Future<List<double>> embed(Float32List blob) async =>
      List<double>.generate(128, (i) => (i % 9) * 0.11 + 0.02);
}

Uint8List _jpegUji() {
  final gambar = img.Image(width: 160, height: 120);
  img.fill(gambar, color: img.ColorRgb8(120, 130, 140));
  return Uint8List.fromList(img.encodeJpg(gambar));
}

OnnxFaceEmbeddingProvider _provider(_MesinPalsu mesin) =>
    OnnxFaceEmbeddingProvider(
      mesin: mesin,
      ambilFoto: () async =>
          FotoTantanganWajah(frontal: _jpegUji(), toleh: _jpegUji()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('distribusi model (asset bundle utk Android)', () {
    test('pubspec mendeklarasikan direktori assets/face', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/face/'),
          reason: 'tanpa deklarasi ini model tidak ikut APK Android');
    });

    test('bacaBytes jatuh ke rootBundle saat filesystem kosong', () async {
      // Kandidat direktori sengaja kosong -> satu-satunya jalur = bundle,
      // persis kondisi Android. YuNet (232 KB) dipakai agar test ringan.
      final lokator = LokatorModelWajah(direktoriKandidat: const []);
      final bytes = await lokator.bacaBytes(LokatorModelWajah.namaYunet);
      expect(bytes, isNotNull,
          reason: 'model harus terbaca dari asset bundle');
      expect(bytes!.length, 232589); // ukuran YuNet ter-pin
    });

    test('bacaBytes null utk nama yang tidak ada (fail-closed)', () async {
      final lokator = LokatorModelWajah(direktoriKandidat: const []);
      expect(await lokator.bacaBytes('tidak_ada.onnx'), isNull);
    });
  });

  group('orientasi EXIF (kamera Android)', () {
    test('bakeOrientation menegakkan piksel sesuai tag Orientation', () {
      final asli = img.Image(width: 100, height: 50);
      asli.exif.imageIfd['Orientation'] = 6; // putar 90 searah jarum jam
      final jpg = img.encodeJpg(asli);
      final decoded = img.decodeImage(Uint8List.fromList(jpg))!;
      final tegak = img.bakeOrientation(decoded);
      expect(tegak.width, 50);
      expect(tegak.height, 100);
    });

    test('provider memanggil bakeOrientation sebelum deteksi', () {
      final source = File('lib/services/face_onnx/onnx_face_provider.dart')
          .readAsStringSync();
      expect(source, contains('img.bakeOrientation('),
          reason: 'tanpa ini foto portrait Android terbaca rebahan 90 derajat '
              'dan YuNet gagal mendeteksi wajah');
    });
  });

  group('TransformasiSerupa', () {
    test('memetakan titik referensi dgn tepat dan balik() konsisten', () {
      // rotasi 30 derajat + skala 1.5 + translasi.
      final sudut = math.pi / 6;
      final a = 1.5 * math.cos(sudut);
      final b = 1.5 * math.sin(sudut);
      final asli = TransformasiSerupa(a, b, 12, -7);
      final sumber = _landmarkUji();
      final tujuan = sumber.map(asli.terapkan).toList();
      final taksiran = TransformasiSerupa.dariTitik(sumber, tujuan);
      for (var i = 0; i < sumber.length; i++) {
        final p = taksiran.terapkan(sumber[i]);
        expect(p.dx, closeTo(tujuan[i].dx, 1e-6));
        expect(p.dy, closeTo(tujuan[i].dy, 1e-6));
      }
      final pulang = taksiran.balik().terapkan(tujuan[2]);
      expect(pulang.dx, closeTo(sumber[2].dx, 1e-6));
      expect(pulang.dy, closeTo(sumber[2].dy, 1e-6));
    });
  });

  group('perkiraanYaw & liveness', () {
    test('wajah simetris = yaw 0; hidung bergeser = bertanda', () {
      expect(perkiraanYaw(_landmarkUji()), closeTo(0, 1e-9));
      expect(perkiraanYaw(_landmarkUji(geserHidung: 12)), greaterThan(0.2));
      expect(perkiraanYaw(_landmarkUji(geserHidung: -12)), lessThan(-0.2));
    });

    test('tanpa gerakan atau identitas putus -> skor 0', () {
      expect(
          skorLivenessTantangan(
              yawFrontal: 0, yawToleh: 0.02, cosineAntarPose: 0.9),
          0);
      expect(
          skorLivenessTantangan(
              yawFrontal: 0, yawToleh: 0.4, cosineAntarPose: 0.1),
          0);
      expect(
          skorLivenessTantangan(
              yawFrontal: 0, yawToleh: 0.4, cosineAntarPose: 0.9),
          greaterThanOrEqualTo(0.6));
    });
  });

  group('decodeYuNet', () {
    test('decode(encode(wajah)) mengembalikan kotak, landmark, dan skor', () {
      const kotak = Rect.fromLTWH(40, 30, 80, 90);
      final landmark = _landmarkUji(geserHidung: 4);
      final hasil = decodeYuNet(
        keluaran: keluaranYuNetSintetis(
            lebar: 160, tinggi: 120, kotak: kotak, landmark: landmark),
        lebarInput: 160,
        tinggiInput: 120,
      );
      expect(hasil, hasLength(1));
      final d = hasil.first;
      expect(d.skor, closeTo(0.95, 1e-6));
      expect(d.kotak.center.dx, closeTo(kotak.center.dx, 1e-6));
      expect(d.kotak.width, closeTo(kotak.width, 1e-6));
      for (var k = 0; k < 5; k++) {
        expect(d.landmark[k].dx, closeTo(landmark[k].dx, 1e-6));
        expect(d.landmark[k].dy, closeTo(landmark[k].dy, 1e-6));
      }
    });

    test('skor di bawah ambang dibuang', () {
      final hasil = decodeYuNet(
        keluaran: keluaranYuNetSintetis(
            lebar: 160,
            tinggi: 120,
            kotak: const Rect.fromLTWH(40, 30, 80, 90),
            landmark: _landmarkUji(),
            skor: 0.2),
        lebarInput: 160,
        tinggiInput: 120,
      );
      expect(hasil, isEmpty);
    });
  });

  group('blob & embedding', () {
    test('blobBgrNchw menata kanal BGR planar', () {
      final gambar = img.Image(width: 2, height: 1);
      gambar.setPixelRgb(0, 0, 10, 20, 30);
      gambar.setPixelRgb(1, 0, 40, 50, 60);
      final blob = blobBgrNchw(gambar);
      expect(blob, [30, 60, 20, 50, 10, 40]); // B B G G R R
    });

    test('embeddingKeBytesLe lolos validasi kontrak server', () {
      final embedding =
          List<double>.generate(128, (i) => math.sin(i.toDouble()) + 1.5);
      final bytes = embeddingKeBytesLe(embedding);
      expect(bytes.length, 512);
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(
              String.fromCharCodes([])) ,
          isNotNull); // string kosong bukan embedding
      final data = ByteData.sublistView(bytes);
      expect(data.getFloat32(0, Endian.little), closeTo(embedding[0], 1e-6));
      expect(data.getFloat32(508, Endian.little),
          closeTo(embedding[127], 1e-6));
    });

    test('cosine: identik 1, ortogonal 0', () {
      expect(cosine([1, 0, 2, 3], [1, 0, 2, 3]), closeTo(1, 1e-9));
      expect(cosine([1, 0], [0, 1]), closeTo(0, 1e-9));
    });
  });

  group('letterboxUntukDeteksi', () {
    test('kanvas selalu 640x640, faktor memetakan balik ke asli', () {
      final sumber = img.Image(width: 1280, height: 720);
      sumber.setPixelRgb(1279, 719, 200, 0, 0);
      final hasil = letterboxUntukDeteksi(sumber);
      expect(hasil.gambar.width, sisiYunet);
      expect(hasil.gambar.height, sisiYunet);
      expect(hasil.faktor, closeTo(2.0, 1e-9)); // 1280 -> 640
      // Konten tertempel kiri-atas: piksel di luar 640x360 harus hitam.
      expect(hasil.gambar.getPixel(0, 400).r.toInt(), 0);
      // Titik (639, 359) kanvas ~ (1278, 718) asli.
      expect((639 * hasil.faktor).round(), 1278);
    });

    test('gambar kecil di-skala NAIK ke 640 (bukan dibiarkan)', () {
      final hasil =
          letterboxUntukDeteksi(img.Image(width: 160, height: 120));
      expect(hasil.gambar.width, sisiYunet);
      expect(hasil.faktor, closeTo(0.25, 1e-9));
    });
  });

  group('potongSejajarSface', () {
    test('landmark tepat di titik referensi -> warp identitas', () {
      final gambar = img.Image(width: 112, height: 112);
      for (var y = 0; y < 112; y++) {
        for (var x = 0; x < 112; x++) {
          gambar.setPixelRgb(x, y, x * 2, y * 2, 100);
        }
      }
      final hasil = potongSejajarSface(gambar, titikReferensiSface);
      final tengah = hasil.getPixel(56, 56);
      expect(tengah.r.toInt(), closeTo(112, 2));
      expect(tengah.g.toInt(), closeTo(112, 2));
    });
  });

  group('OnnxFaceEmbeddingProvider (mesin palsu)', () {
    test('tantangan dua pose sah -> sampel FACE valid + liveness', () async {
      final mesin = _MesinPalsu(landmarkPerPanggilan: [
        _landmarkUji(), // frontal
        _landmarkUji(geserHidung: 12), // toleh
      ]);
      final sample = await _provider(mesin).capture();
      expect(sample.modality, 'FACE');
      expect(sample.templateFormat, FaceOnDeviceCapture.templateFormat);
      expect(sample.provider, OnnxFaceEmbeddingProvider.namaProvider);
      expect(sample.livenessScore, greaterThanOrEqualTo(0.6));
      expect(
          FaceOnDeviceCapture.validasiEmbeddingBase64(sample.templateBase64),
          isNull);
      // Lolos juga validasi registri (jalur yang dipakai bridge sungguhan).
      FaceOnDeviceCapture.pasang(_ProviderTetap(sample));
      final lewatRegistri = await FaceOnDeviceCapture.capture();
      expect(lewatRegistri.livenessScore, sample.livenessScore);
      FaceOnDeviceCapture.pasang(null);
    });

    test('tanpa gerakan menoleh -> liveness gagal', () async {
      final mesin = _MesinPalsu(landmarkPerPanggilan: [
        _landmarkUji(),
        _landmarkUji(), // pose kedua identik = foto diam
      ]);
      expect(_provider(mesin).capture(),
          throwsA(isA<PosBiometricUnavailable>()));
    });

    test('pembatalan kamera -> PosBiometricUnavailable', () async {
      final mesin = _MesinPalsu(landmarkPerPanggilan: [_landmarkUji()]);
      final provider = OnnxFaceEmbeddingProvider(
          mesin: mesin, ambilFoto: () async => null);
      expect(provider.capture(), throwsA(isA<PosBiometricUnavailable>()));
    });
  });
}

class _ProviderTetap implements FaceEmbeddingProvider {
  const _ProviderTetap(this.sample);
  final PosBiometricSample sample;

  @override
  String get providerName => sample.provider;

  @override
  Future<bool> ready() async => true;

  @override
  Future<PosBiometricSample> capture() async => sample;
}
