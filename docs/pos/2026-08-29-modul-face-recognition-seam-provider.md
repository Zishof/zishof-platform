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

## Yang DIBUTUHKAN untuk gelombang 2 (implementasi provider nyata)

1. **Aset model**: berkas `.tflite` MobileFaceNet (atau setara) beserta bukti
   lisensinya — perlu keputusan/berkas dari pemilik produk; tidak diunduh
   sembarangan.
2. **Dependensi pub**: `tflite_flutter` (Android + Windows), deteksi wajah
   (`google_mlkit_face_detection` untuk Android; Windows perlu detektor
   TFLite mis. BlazeFace karena ML Kit tidak tersedia di desktop), dan
   `camera`/`camera_windows` untuk aliran frame.
3. **Liveness aktif**: tantangan kedip/toleh dengan skor gabungan — bukan
   anti-spoof bersertifikat; keterbatasan ini wajib jujur di release notes.
4. **Kalibrasi ambang**: `AIS_BIOMETRIC_FACE_THRESHOLD` dan ambang liveness
   dikalibrasi dengan subjek berizin saat UAT — jangan menebak angka.

Sampai provider nyata terpasang, seluruh jalur wajah tetap fail-closed —
tidak ada gate yang dipalsukan.
