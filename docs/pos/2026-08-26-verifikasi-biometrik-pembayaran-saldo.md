# Verifikasi biometrik sebelum pembayaran saldo member

## Keputusan

Jenis Member mempunyai dua aturan independen: **Wajib Verifikasi Biometric
Wajah** dan **Wajib Verifikasi Fingerprint**. Aturan hanya menjadi gerbang ketika
metode pembayaran benar-benar memotong deposit/saldo member. Bila keduanya
aktif, keduanya harus berhasil; PIN tidak menggantikan biometric yang wajib.

Pembayaran biasa tetap local-first. Pembayaran saldo yang mewajibkan biometric
harus online dan menunggu pengakuan server karena bukti biometric berumur lima
menit. Menaruh bukti tersebut dalam antrean offline akan menghasilkan transaksi
yang baru dikirim setelah buktinya kedaluwarsa.

## Alur

```text
Kasir memilih member dan metode pembayaran
                 |
                 v
Apakah metode memotong saldo dan jenis member mewajibkan biometric?
       | tidak                              | ya
       v                                    v
Simpan lokal -> outbox             Periksa SDK/perangkat
-> retry idempoten                         |
                                  capture wajah/fingerprint
                                             |
                                  server mencocokkan template
                                             |
                                  event MATCHED + kode transaksi
                                             |
                                  checkout mengirim event_id
                                             |
                                  server memvalidasi ulang:
                                  kasir, member, modality,
                                  kode transaksi, umur <= 5 menit
                                             |
                                  potong saldo + ACK server
                                             |
                                  simpan salinan transaksi lokal
```

## Batas perangkat

- Baseline scanner Desktop adalah **SecuGen Hamster Pro 20**. Flutter POS
  berbicara dengan layanan lokal resmi SecuGen WebAPI/SgiBioSrv pada
  `https://localhost:8000/SGIFPCapture` dan meminta template
  `ISO_19794_2`. Respons gambar sidik jari tidak disimpan oleh aplikasi.
- Status port 8000 hanya berarti layanan vendor terdeteksi. Kesiapan scanner,
  lisensi, jari, dan kualitas sampel tetap divalidasi pada saat capture.
- Kamera harus disertai face embedding dan pemeriksaan liveness; foto biasa
  tidak dianggap bukti biometric.
- Sensor fingerprint bawaan Android pada umumnya hanya mengautentikasi pemilik
  perangkat melalui Android Keystore dan tidak mengekspor template sidik jari.
  Sensor tersebut tidak dapat dipakai mencocokkan banyak member. Untuk kasus
  kasir diperlukan scanner eksternal/terminal khusus beserta vendor SDK.
- Jika perangkat/metode wajib tidak tersedia, pembayaran saldo dihentikan
  secara fail-closed. Kasir dapat memilih metode pembayaran non-saldo.

## Data dan keamanan

- Server menyimpan template terenkripsi, bukan foto mentah.
- Bukti checkout berupa ID `BiometricEvent`, bukan template/probe.
- Event diikat ke actor, subject, modality, purpose `POS_PURCHASE`, dan
  `reference_id = kodeUnik` sehingga tidak dapat digunakan untuk transaksi lain.
- Perubahan kebijakan Jenis Member diaudit oleh Hibernate Envers.
- Snapshot aturan disimpan dalam `anggota_cache` agar UI offline tidak salah
  menampilkan kebijakan yang lebih longgar.

## Kontrak adapter perangkat

Flutter memakai `MethodChannel` bernama `ais_mobile/biometric_capture`. Adapter
native Windows/Android wajib menyediakan dua operasi berikut:

1. `capabilities` mengembalikan `fingerprint`, `face`, dan `reason`. Nilai
   `true` hanya boleh diberikan bila perangkat, driver/SDK, dan proses capture
   benar-benar siap.
2. `captureProbe` menerima `modality` (`FINGERPRINT` atau `FACE`) dan
   mengembalikan `modality`, `templateBase64`, `templateFormat`, `provider`,
   serta `livenessScore` untuk wajah.

Template fingerprint harus memakai format yang dipahami matcher vendor
(baseline AIS: `ISO_19794_2`). Sampel wajah bukan JPEG/foto; adapter harus
menghasilkan embedding `FACE_EMBEDDING_F32_LE_V1` dan skor liveness. Flutter
menolak Base64 rusak, modalitas yang tertukar, provider/format kosong, dan
payload di atas 64 KiB.

Kesiapan selalu diperiksa dua lapis:

- **Enrollment:** izin pengelola + kunci enkripsi server + SDK perangkat.
- **Verifikasi transaksi:** kunci enkripsi + SDK perangkat + matcher server.

Karena itu slot dapat dipersiapkan sebelum matcher vendor aktif, tetapi kasir
tetap berhenti secara fail-closed sampai matcher tersedia.

## Konfigurasi server

- `AIS_BIOMETRIC_MASTER_KEY_BASE64`: kunci AES utama (wajib; jangan dimasukkan
  ke source, log, atau paket rilis).
- `AIS_BIOMETRIC_KEY_VERSION`: versi kunci aktif.
- `AIS_BIOMETRIC_MATCHER_CLASS`: implementasi
  `BiometricMatcherProvider` dari SDK fingerprint vendor.
- `AIS_BIOMETRIC_FACE_THRESHOLD`: ambang cosine face embedding; default `0.82`.
- `AIS_BIOMETRIC_LIVENESS_THRESHOLD`: ambang liveness wajah; default `0.70`.
- `AIS_BIOMETRIC_MAX_OFFLINE_MINUTES`: umur maksimum bukti; default 1.440
  menit, sedangkan checkout POS tetap memakai event transaksi yang berumur
  pendek.

Endpoint `biometrik_kemampuan` harus melaporkan
`server_encryption_ready=true` dan matcher modalitas terkait `true` sebelum
fitur transaksi dinyatakan siap.

## Instalasi perangkat Desktop SecuGen

1. Pasang driver resmi Hamster Pro 20 dan SecuGen WebAPI/SgiBioSrv pada mesin
   kasir Windows.
2. Aktifkan lisensi/domain key sesuai perjanjian vendor. Jangan menaruh kunci
   lisensi di source, log, atau paket publik.
3. Pastikan layanan hanya didengar pada loopback port 8000. POS menolak endpoint
   non-HTTPS, host non-loopback, dan port selain 8000.
4. Pasang implementasi `BiometricMatcherProvider` vendor beserta DLL/runtime
   matcher di server AIS, lalu set `AIS_BIOMETRIC_MATCHER_CLASS` ke nama kelas
   tersebut.
5. Pastikan `biometrik_kemampuan` melaporkan enkripsi dan matcher fingerprint
   siap sebelum membuka pembayaran yang mewajibkan fingerprint.

Tanpa matcher vendor di server, enrollment dapat merekam slot bila enkripsi
siap, tetapi pembayaran tetap ditolak secara fail-closed. Aplikasi tidak
menganggap template ISO sama hanya dengan membandingkan byte mentah.

## Integrasi Android dan wajah

- Android tetap memerlukan scanner SecuGen eksternal USB/OTG dan paket Android
  SDK vendor (AAR/JAR serta library native ABI). `BiometricPrompt` bawaan hanya
  mengautentikasi pemilik perangkat dan tidak dapat mengekspor template sidik
  jari member AIS.
- Face recognition memerlukan kamera, deteksi liveness, alignment wajah, dan
  model embedding yang menghasilkan `FACE_EMBEDDING_F32_LE_V1`. Foto JPEG/PNG
  bukan template pengenalan dan tidak pernah diterima sebagai pengganti.
- Sampai provider face-liveness nyata dipasang, kemampuan wajah dilaporkan
  `false`; enrollment dan pembayaran yang mewajibkannya berhenti fail-closed.
- Build Android memasang channel native `ais_mobile/biometric_capture` secara
  eksplisit. Selama AAR/JAR dan library ABI vendor belum dipasang, respons
  kemampuan adalah `fingerprint=false` dan `face=false`; permintaan rekam
  mengembalikan `BIOMETRIC_VENDOR_SDK_REQUIRED`. Ini mencegah UI menganggap
  sensor bawaan Android sebagai scanner member AIS.

## Kebijakan local-first

Metadata slot (modalitas, jari/pose, provider, revisi, status) boleh disimpan di
cache lokal agar layar cepat dibuka. Template mentah, probe, embedding wajah,
foto wajah, dan event verifikasi **tidak** disimpan di cache atau outbox.
Enrollment dan verifikasi selalu online. Kebijakan ini sengaja berbeda dari
CRUD master biasa karena material biometrik sensitif dan bukti transaksi dapat
kedaluwarsa.

## Matriks penerimaan perangkat

Sebelum sebuah adapter dinyatakan siap, UAT perangkat nyata wajib mencakup:

- lima slot fingerprint dan lima slot wajah per member;
- rekam baru, rekam ulang, nonaktifkan, dan muat ulang metadata;
- template tidak pernah muncul di SQLite, log, clipboard, atau respons daftar;
- sampel salah modalitas/format/provider ditolak;
- wajah tanpa liveness atau di bawah ambang ditolak;
- jari/wajah bukan pemilik ditolak dan pemilik diterima pada ambang yang sudah
  dikalibrasi;
- scanner dicabut, kamera ditolak, timeout, server offline, dan matcher mati
  semuanya menghentikan transaksi tanpa memotong saldo;
- satu event tidak dapat dipakai ulang untuk transaksi/member/kasir lain.

## Integrasi SDK vendor yang masih diperlukan

Implementasi Flutter, kontrak channel, enkripsi, matcher face bawaan, adapter
matcher fingerprint, slot, hak akses, dan gerbang checkout sudah tersedia.
Bagian yang tidak dapat dibuat generik tanpa artefak vendor adalah implementasi
native scanner Windows/USB-OTG dan mesin face embedding+liveness. Setelah vendor
dipilih, library/driver berlisensi vendor dipasang di adapter channel tersebut,
kemudian seluruh matriks UAT di atas harus dijalankan pada perangkat produksi.
## Pemeriksaan kesiapan sebelum UAT

Jalankan `apps/ebisnis/tool/check_biometric_readiness.ps1` dengan
`AIS_BIOMETRIC_API_URL` dan `AIS_BIOMETRIC_UAT_TOKEN` di environment. Skrip
memeriksa layanan SecuGen Desktop, enkripsi server, matcher fingerprint,
matcher wajah, dan hak enrollment. Token tidak dicetak. Panel Member juga
menampilkan matriks diagnosis yang sama; tombol perekaman/verifikasi tetap
dinonaktifkan bila komponen wajib belum siap.

Self-test inti backend dapat dijalankan dari root `src/main` dengan kelas
`ais.action.servlet.api.biometric.test.BiometricCoreSelfTest`. Pengujian ini
memastikan AES-GCM dapat didekripsi kembali, perubahan AAD ditolak, ciphertext
tidak memuat template polos, serta matcher wajah menerima sampel dekat dan
menolak sampel berlawanan. Self-test perangkat fisik tetap harus mengikuti
matriks UAT karena tidak dapat digantikan oleh simulasi perangkat lunak.
