# Modul Face Recognition — seam provider on-device (gelombang 1)

Tanggal: 29 Agustus 2026  
Konteks: alat fingerprint belum tersedia; pemilik produk memutuskan melanjutkan
modul wajah lebih dulu dengan pendekatan **on-device open-source**
(MobileFaceNet/TFLite + deteksi-alignment wajah + liveness aktif berbasis
tantangan). Prasyaratnya dipenuhi lebih dulu: diff biometrik tertunda
di-commit terpisah (`c883917`) sehingga pekerjaan wajah mulai dari tree bersih.

## Peta kondisi (hasil audit source)

- **Server SIAP.** Matcher wajah bawaan `AIS_COSINE_FACE_V1` di
  `BiometricMatcherRegistry.java`: cosine similarity atas embedding
  `FACE_EMBEDDING_F32_LE_V1` (float32 little-endian, minimal 16 byte,
  kelipatan 4, tolak NaN/Infinity), ambang `AIS_BIOMETRIC_FACE_THRESHOLD`
  (default 0.82, kalibrasi saat UAT). Enkripsi + audit + self-test lulus
  di r78487.
- **Klien belum punya penghasil embedding.** Bridge Flutter menunggu provider
  di MethodChannel `ais_mobile/biometric_capture`; Android sengaja
  fail-closed; kamera Desktop terdeteksi tetapi tidak ada yang mengubah frame
  menjadi embedding. Server sengaja TIDAK menerima foto mentah.

## Yang dibangun pada gelombang 1

`lib/services/face_embedding_provider.dart`:

- `FaceEmbeddingProvider` — kontrak implementasi nyata: `providerName`
  (tercatat di audit server), `ready()` (model termuat + kamera siap),
  `capture()` (deteksi → tantangan liveness → embedding float32 LE).
- `FaceOnDeviceCapture` — registri (`pasang()` saat startup varian) +
  **validasi cermin matcher server** sebelum sampel dikirim: format wajib
  `FACE_EMBEDDING_F32_LE_V1`, Base64 sah, panjang kelipatan 4 ≥ 16 byte
  ≤ 64 KiB, tanpa NaN/Infinity, bukan vektor nol, dan **skor liveness wajib
  ada** (foto diam bukan bukti biometrik). Provider yang salah gagal di
  perangkat dengan pesan jelas, bukan diam-diam ditolak matcher.

`biometric_capture_bridge.dart` — wiring simetris dengan pola SecuGen
fingerprint: `capabilities()` melaporkan `face: true` + `face_provider` hanya
bila provider terpasang dan siap; `capture('FACE')` dirutekan ke provider
on-device; tanpa provider semuanya tetap fail-closed (channel native tetap
menjadi fallback untuk SDK vendor).

Test `test/face_embedding_provider_test.dart` (14 test): validasi embedding
(sah/NaN/nol/kependekan/kelebihan 64 KiB/bukan Base64), fail-closed tanpa
provider, penolakan format salah dan liveness kosong, serta integrasi bridge
dengan provider palsu. Catatan test: integrasi bridge memakai `test()` biasa
dengan endpoint SecuGen non-loopback — socket sungguhan menggantung di zona
fake-async `testWidgets`.

## Model terpilih (disetujui pemilik produk, diunduh 29 Agustus 2026)

Sumber: **OpenCV Zoo** (repositori resmi organisasi OpenCV) — sumber paling
defensibel secara lisensi. Teks LICENSE diverifikasi langsung dari repo dan
salinannya disimpan di `apps/ebisnis/assets/face/`.

| Peran | Berkas | Lisensi | Ukuran | SHA-256 |
|---|---|---|---|---|
| Embedding wajah (128-dim float32) | `face_recognition_sface_2021dec.onnx` | Apache-2.0 | 38,7 MB | `0BA9FBFA01B5270C96627C4EF784DA859931E02F04419C829E83484087C34E79` |
| Deteksi wajah | `face_detection_yunet_2023mar.onnx` | MIT © 2020 Shiqi Yu | 232 KB | `8F2383E4DD3CFBB4553EA8718107FC0423210DC964F9F4280604804ED2552FA4` |

Yang DITOLAK dan alasannya: bobot InsightFace/ArcFace (eksplisit
non-komersial/research-only) dan `mobilefacenet.tflite` dari repo perorangan
(provenance bobot tidak jelas).

Binari model **tidak disimpan di git** (SFace 38,7 MB akan membengkakkan
riwayat permanen). Sumber kebenarannya `tool/unduh_model_wajah.ps1`: URL
ter-pin + verifikasi SHA-256 wajib cocok (berkas dibuang bila beda), aman
diulang. `assets/face/*.onnx` masuk `.gitignore`; salinan LICENSE ikut git.

Konsekuensi format: model ONNX (bukan TFLite), sehingga runtime inferensi
gelombang 2 memakai **ONNX Runtime**, bukan `tflite_flutter`. Ukuran SFace
fp32 juga menuntut keputusan bundling APK (kandidat: varian int8 opencv_zoo
atau unduhan saat aktivasi fitur) — diputuskan di gelombang 2.

## Yang DIBUTUHKAN untuk gelombang 2 (implementasi provider nyata)

1. ~~Aset model~~ — SELESAI (tabel di atas).
2. **Dependensi pub**: runtime ONNX untuk Flutter (Windows + Android) dan
   `camera`/`camera_windows` untuk aliran frame — persetujuan versi saat
   integrasi.
3. **Liveness aktif**: tantangan kedip/toleh dengan skor gabungan — bukan
   anti-spoof bersertifikat; keterbatasan ini wajib jujur di release notes.
4. **Kalibrasi ambang**: `AIS_BIOMETRIC_FACE_THRESHOLD` dan ambang liveness
   dikalibrasi dengan subjek berizin saat UAT — jangan menebak angka.

Sampai provider nyata terpasang, seluruh jalur wajah tetap fail-closed —
tidak ada gate yang dipalsukan.
