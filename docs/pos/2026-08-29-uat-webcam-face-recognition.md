# UAT webcam face recognition — Desktop Windows (gelombang 2b)

Tanggal persiapan: 29 Agustus 2026  
Build: `flutter build windows --release` varian default, dari commit `1d45537`
(provider wajah on-device) — build UAT internal, BUKAN artefak rilis.

## Prasyarat di mesin UAT

1. Webcam terpasang (mesin ini: 2 kamera terdeteksi — PASS readiness).
2. Model wajah. Sejak keputusan distribusi asset-bundle (29 Agustus 2026),
   build yang dibuat DENGAN model di `assets/face` sudah membawa modelnya
   di dalam bundle — tidak perlu salin manual. Folder `assets\face` di
   samping exe / env `AIS_FACE_MODEL_DIR` tetap berfungsi sbg override
   operasional. Bila build dibuat tanpa model: jalankan
   `tool\unduh_model_wajah.ps1` sebelum build.
3. Server AIS terjangkau dan akun UAT punya izin enrollment biometrik
   (`boleh_enroll_pengguna_lain`), master key biometrik server aktif
   (`server_encryption_ready` dari `biometrik_kemampuan`).
4. Subjek uji yang BERIZIN. Jangan merekam wajah siapa pun tanpa persetujuan.

## Jalur eksekusi

Jalankan `build\windows\x64\runner\Release\ebisnis.exe` dari folder Release
(agar `assets\face` di sampingnya ditemukan lokator; alternatif: set
`AIS_FACE_MODEL_DIR` ke folder model).

## Matriks UAT minimum

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| 1 | Login akun UAT → panel biometrik member → cek diagnosa wajah | "Kamera + face-liveness" = siap, provider `AIS_ONDEVICE_SFACE_V1`; matcher wajah server siap |
| 2 | Rekam wajah subjek berizin (tantangan 2 pose: lurus → menoleh) | Layar kamera terbuka, dua potret, slot wajah terisi di server |
| 3 | Rekam ulang dgn pose kedua IDENTIK (tidak menoleh) | DITOLAK: "Tantangan liveness gagal" |
| 4 | Rekam dgn dua orang di depan kamera | DITOLAK: "lebih dari satu wajah" |
| 5 | Rekam tanpa wajah (arahkan ke dinding) | DITOLAK: "Wajah tidak terdeteksi" |
| 6 | Verifikasi checkout saldo member dgn wajah pemilik | MATCH; transaksi lanjut |
| 7 | Verifikasi dgn wajah orang lain (berizin) | TIDAK match; transaksi berhenti (fail-closed) |
| 8 | Cabut model (`assets\face` dipindah) → restart → coba rekam | Fail-closed dgn pesan "jalankan tool/unduh_model_wajah.ps1" |
| 9 | Matikan jaringan → coba rekam/verifikasi | Berhenti dgn pesan jelas (enrollment/verifikasi online-only) |
| 10 | Periksa log/DB lokal | TIDAK ada embedding/foto mentah di SQLite, outbox, atau log |

Catat skor cosine yang muncul di sisi server utk kalibrasi
`AIS_BIOMETRIC_FACE_THRESHOLD` (default 0.82) — kumpulkan skor match-benar
dan match-salah dari beberapa subjek berizin sebelum mengubah ambang.

## Hasil UAT (berjalan)

- **29 Agustus 2026 — langkah 1–2 LULUS.** Percobaan pertama gagal ("wajah
  tidak terdeteksi"); dua akar masalah ditemukan lewat diagnostik headless
  (`tool/diagnostik/face_onnx_diagnostik_test.dart`) dan diperbaiki di commit
  `b2d8f20`: (1) `OrtSession.fromFile` salah encoding path di Windows —
  model tidak pernah termuat; (2) YuNet ONNX bermasukan TETAP 640x640 —
  kini di-letterbox. Setelah rebuild: wajah terdeteksi, tantangan dua pose
  berjalan, dan **enrollment sampai ke server** — membuktikan rantai penuh
  kamera -> YuNet -> alignment -> SFace -> liveness -> `biometrik_simpan` ->
  enkripsi server bekerja (master key server aktif).
- **29 Agustus 2026 — langkah 3–10 LULUS SEMUA** (dinyatakan pemilik produk
  setelah menjalankan matriks): pose kedua identik ditolak liveness (3),
  lebih dari satu wajah ditolak (4), tanpa wajah ditolak (5), verifikasi
  checkout wajah pemilik MATCH (6), wajah orang lain TIDAK match dan
  transaksi berhenti fail-closed (7), model dicabut -> fail-closed dgn
  petunjuk unduh (8), offline -> berhenti dgn pesan jelas (9), dan tidak
  ada embedding/foto mentah di SQLite/outbox/log lokal (10).
- **Matriks UAT webcam Desktop LENGKAP.** Ambang masih default server
  (`AIS_BIOMETRIC_FACE_THRESHOLD` 0.82) — perilaku match/tolak lulus pada
  default ini; kalibrasi berbasis kumpulan skor cosine multi-subjek tetap
  disarankan sebelum produksi bila populasi member besar.

## UAT kamera Android (menyusul; APK model-termasuk sudah siap)

Pasang `app-ebisnis-release.apk` via `adb install -r`. Matriks = cermin
langkah 1–10 Desktop, ditambah perhatian khusus Android:

- **Izin kamera runtime**: dialog permission harus muncul saat layar kamera
  pertama dibuka (manifest sudah punya `android.permission.CAMERA`); tolak
  izin -> perekaman gagal dgn pesan jelas, bukan crash.
- **Orientasi**: uji perekaman dgn HP PORTRAIT — JPEG kamera Android membawa
  rotasi via EXIF; pipeline menegakkannya (`bakeOrientation`, ditambahkan
  sebelum UAT Android setelah gap ini teridentifikasi). Uji juga landscape.
- **Kamera depan**: provider memprioritaskan lensa depan; pratinjau mirror
  adalah tampilan saja. Enrollment dan verifikasi pada perangkat yang sama
  harus konsisten; cocokkan juga lintas perangkat (enroll Desktop ->
  verifikasi Android) dan catat skor cosine-nya.
- **Waktu inferensi ARM**: catat lama deteksi+embedding per pose; bila
  > beberapa detik pada HP kasir, pertimbangkan varian int8.
- **Model dari bundle**: pemuatan lewat rootBundle (bukan folder) — bila
  fail-closed "model belum ada" muncul padahal APK benar, itu bug jalur
  bundle, laporkan.

## Yang secara sadar BELUM diuji di gelombang ini

- Anti-spoof bersertifikat (liveness kita = tantangan aktif).
- Kinerja inferensi pada mesin kasir kelas rendah.
