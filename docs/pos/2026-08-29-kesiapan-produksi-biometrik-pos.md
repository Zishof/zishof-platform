# Kesiapan produksi biometrik POS

Tanggal audit: 29 Agustus 2026  
Ruang lingkup: POS Desktop dan Android varian Al-Bahjah/Nahl, API AIS, enrollment member, serta verifikasi pembayaran saldo.

## Kesimpulan eksekutif

Lapisan perangkat lunak generik biometrik **selesai dan lulus pengujian otomatis**. Sistem menyediakan lima slot fingerprint dan lima slot wajah per member, menyimpan template terenkripsi AES-256-GCM di server, tidak memasukkan template/probe ke cache atau outbox, mewajibkan liveness untuk wajah, serta menghentikan transaksi secara fail-closed bila perangkat, enkripsi, matcher, atau bukti verifikasi tidak siap.

Status ini tidak sama dengan siap produksi penuh. Produksi masih memerlukan perangkat nyata, SDK/driver berlisensi vendor, matcher fingerprint server, provider face embedding+liveness, secret server, dan sertifikat penandatanganan rilis. Artefak `1.34.03` yang tersedia adalah paket UAT internal: APK bertanda tangan debug dan installer Windows belum memiliki Authenticode yang valid.

## Bukti yang sudah hijau

- Flutter: **442 test lulus**.
- Kontrak enrollment: lima slot fingerprint dan lima slot wajah divalidasi di UI dan API.
- Backend Java: kompilasi modul biometrik lulus.
- `BiometricCoreSelfTest`: enkripsi/dekripsi, penolakan AAD salah, ciphertext tidak memuat template polos, dan matcher wajah lulus.
- Self-test RBAC menu biometrik lulus.
- Skrip build/release PowerShell lolos parser.
- Guard rilis menolak APK debug dan EXE tanpa Authenticode.
- `git diff --check` lulus; peringatan yang tersisa hanya normalisasi LF/CRLF.

## Kontrak keamanan yang tidak boleh dilonggarkan

1. Template biometrik hanya disimpan dalam ciphertext server; foto mentah, probe, dan template tidak masuk SQLite, outbox, log, clipboard, atau endpoint daftar.
2. Enrollment dan verifikasi selalu online. Metadata slot boleh dicache secara local-first, tetapi material biometrik tidak boleh diantrikan.
3. Wajah wajib memakai embedding `FACE_EMBEDDING_F32_LE_V1` dan skor liveness yang memenuhi ambang server. JPEG/PNG bukan template pengenalan wajah.
4. Fingerprint member Android tidak memakai `BiometricPrompt` bawaan. Android memerlukan scanner eksternal USB/OTG beserta SDK vendor karena sensor perangkat tidak mengekspor template member.
5. Transaksi yang mewajibkan biometrik harus berhenti bila salah satu komponen wajib tidak siap. Tidak ada fallback diam-diam ke transaksi tanpa verifikasi.
6. Event verifikasi diikat ke actor, subject, modality, purpose, dan kode transaksi; event tidak boleh dipakai ulang untuk transaksi lain.

## Konfigurasi produksi

Secret harus diberikan melalui environment/secret manager, tidak pernah melalui source atau paket rilis.

| Variabel | Kegunaan | Gate |
|---|---|---|
| `AIS_BIOMETRIC_MASTER_KEY_BASE64` | Kunci AES 32 byte | Wajib |
| `AIS_BIOMETRIC_KEY_VERSION` | Versi rotasi kunci | Wajib dikelola |
| `AIS_BIOMETRIC_MATCHER_CLASS` | Implementasi matcher fingerprint vendor | Wajib untuk fingerprint |
| `AIS_BIOMETRIC_FACE_THRESHOLD` | Ambang cosine wajah | Kalibrasi UAT |
| `AIS_BIOMETRIC_LIVENESS_THRESHOLD` | Ambang liveness wajah | Kalibrasi UAT |
| `AIS_BIOMETRIC_API_URL` | Endpoint UAT `Api_eBisnis` | Wajib untuk readiness check |
| `AIS_BIOMETRIC_UAT_TOKEN` | Token akun UAT | Wajib untuk readiness check |
| `AIS_RELEASE_STORE_FILE` | Keystore Android produksi | Wajib rilis Android |
| `AIS_RELEASE_STORE_PASSWORD` | Password keystore | Wajib rilis Android |
| `AIS_RELEASE_KEY_ALIAS` | Alias kunci | Wajib rilis Android |
| `AIS_RELEASE_KEY_PASSWORD` | Password alias | Wajib rilis Android |
| `AIS_WINDOWS_SIGNING_THUMBPRINT` | Allowlist sertifikat Authenticode | Wajib rilis Windows |

## Urutan deployment

1. Cadangkan database dan catat revisi SVN/commit Git yang akan dipasang.
2. Pasang perubahan backend AIS dan pastikan mapping entitas biometrik aktif.
   Paket backend reproducible dapat dibuat dengan
   `apps/ebisnis/tool/package_biometric_backend.ps1`; skrip mengompilasi source,
   menjalankan self-test, memvalidasi mapping Hibernate, dan menghasilkan ZIP
   beserta manifest, instruksi mapping, serta checksum tanpa menyalin
   `hibernate.cfg.xml` atau menyertakan secret.
3. Isi secret biometrik melalui environment/secret manager, lalu restart service AIS.
4. Panggil `biometrik_kemampuan`; jangan lanjut bila `server_encryption_ready`, matcher modalitas yang dipakai, atau hak enrollment belum `true`.
5. Pasang driver dan SDK scanner pada mesin kasir. Untuk baseline Desktop SecuGen, pastikan SgiBioSrv hanya tersedia melalui HTTPS loopback port 8000.
6. Pasang provider face embedding+liveness pada Desktop/Android bila fitur wajah diaktifkan.
7. Jalankan `apps/ebisnis/tool/check_biometric_readiness.ps1` dari mesin UAT.
   Gunakan parameter `-ReportPath <path>.json` untuk menghasilkan bukti audit
   terstruktur. Laporan hanya berisi status pemeriksaan dan tidak pernah memuat
   token, master key, password keystore, atau template biometrik.
8. Jalankan matriks UAT perangkat di bawah.
9. Build release menggunakan keystore dan sertifikat produksi.
10. Jalankan `verify_apk_signing.ps1` dan `verify_windows_signing.ps1`; publikasi dilarang bila salah satu gagal.

## Matriks UAT perangkat wajib

- Rekam, tampilkan metadata, rekam ulang, nonaktifkan, dan muat ulang kelima slot fingerprint.
- Rekam, tampilkan metadata, rekam ulang, nonaktifkan, dan muat ulang kelima slot wajah.
- Jari/wajah pemilik diterima; milik orang lain ditolak.
- Wajah tanpa liveness dan wajah di bawah ambang ditolak.
- Format, modalitas, provider, Base64, dan payload melebihi 64 KiB ditolak.
- Scanner dicabut, kamera ditolak, timeout, server offline, enkripsi belum siap, dan matcher mati semuanya menghentikan transaksi tanpa memotong saldo.
- Bukti transaksi kedaluwarsa atau dipakai untuk member/kasir/kode transaksi lain ditolak.
- Pemeriksaan SQLite, outbox, log, clipboard, dan respons daftar memastikan tidak ada template/probe/foto mentah.
- Lima kali enrollment berurutan tidak saling menimpa slot lain.
- Pembayaran yang tidak mewajibkan biometrik tetap mengikuti kebijakan transaksi normal.

## Penandatanganan dan artefak

Paket `apps/ebisnis/release-artifacts/biometric-uat/1.34.03` hanya untuk UAT internal. Guard berikut menjadi sumber keputusan rilis:

- `apps/ebisnis/tool/verify_apk_signing.ps1`: menolak sertifikat Android Debug kecuali mode UAT dinyatakan eksplisit.
- `apps/ebisnis/tool/verify_windows_signing.ps1`: menolak status Authenticode selain `Valid`; `-AllowUnsigned` hanya untuk UAT.
- `apps/ebisnis/tool/package_biometric_backend.ps1`: membuat paket backend dari source yang telah lulus kompilasi dan self-test.

Jangan mengganti nama artefak UAT menjadi produksi. Build produksi harus dibuat ulang setelah secret signing tersedia dan harus menghasilkan checksum baru.

Paket backend lokal yang telah lulus kompilasi, self-test, pemeriksaan isi, dan
verifikasi checksum berada di
`apps/ebisnis/release-artifacts/biometric-backend/ais-biometric-backend-20260831-200044.zip`.
SHA-256 ZIP tersebut adalah
`6b45bd782bd21a754fac5e38cb193a8974ce2fe51fd1d756f419342494a72b44`.
Paket dibuat dari SVN r78617 (working copy backend bersih) dan kini JUGA
memuat `KantinHelper` — sebelumnya kelas itu hanya terkompilasi transitif dan
tidak pernah disalin ke bundle, sehingga perbaikan di dalamnya (mis. validasi
barcode unik per toko) tidak akan ter-deploy. Paket tidak memuat konfigurasi
Hibernate server, kredensial, token, master key, template, atau probe biometrik.
Langkah deployment rinci: `2026-08-31-deployment-backend-biometrik-ubuntu.md`.

Paket lama `ais-biometric-backend-20260829-015438.zip` (r78484, SHA-256
`9ed565af...bb24b`) USANG — jangan dipakai untuk deployment baru.

## Pemicu rollback

Rollback aplikasi/backend atau nonaktifkan kebijakan biometrik jika terjadi salah satu kondisi berikut:

- template/probe/foto mentah muncul di cache, outbox, log, atau respons API;
- transaksi saldo lolos tanpa bukti yang diwajibkan;
- false accept melampaui ambang yang disepakati;
- event dapat dipakai ulang lintas member/transaksi;
- enkripsi atau matcher tidak siap setelah restart;
- aplikasi menganggap scanner siap ketika driver/SDK/perangkat tidak tersedia;
- build produksi tidak lolos verifikasi signature.

## Status akhir

| Area | Status |
|---|---|
| Implementasi generik Flutter/API | Selesai |
| Lima slot fingerprint + lima slot wajah | Selesai |
| Enkripsi server dan audit tanpa template | Selesai |
| Fail-closed checkout | Selesai |
| Pengujian otomatis | Lulus |
| SDK scanner fisik + matcher vendor | Menunggu vendor/perangkat |
| Provider face embedding+liveness nyata | Menunggu provider/perangkat |
| UAT perangkat fisik | Belum dapat dijalankan di lingkungan ini |
| Signing Android/Windows produksi | Menunggu secret/sertifikat |
| Publikasi produksi | Diblokir sampai semua gate eksternal hijau |

## Hasil audit mesin pengembangan 29 Agustus 2026

- Kamera terdeteksi dan dapat dipakai untuk tahap integrasi wajah.
- SecuGen WebAPI belum aktif pada HTTPS loopback port 8000; UAT fingerprint
  fisik belum dapat dijalankan di mesin ini.
- Endpoint produksi dapat dijangkau, tetapi benar menolak permintaan tanpa
  token dengan HTTP 401.
- Variabel runtime biometrik dan token UAT tidak tersedia di environment mesin
  pengembangan; nilainya tidak dicari dari source, log, atau penyimpanan lain.
- Satu sertifikat code-signing Windows yang masih valid terdeteksi, tetapi
  thumbprint allowlist produksi belum dikonfigurasi.
- `android/key.properties` dan variabel signing Android produksi tidak tersedia.

Status tersebut adalah gate eksternal, bukan kegagalan implementasi aplikasi.
Jangan mengubah pemeriksaan menjadi lolos semu; pasang perangkat/provider dan
secret melalui jalur operasional resmi, lalu jalankan ulang readiness check.
