# Deployment backend biometrik ke server Ubuntu 20.04

Tanggal: 31 Agustus 2026  
Paket rujukan: `ais-biometric-backend-20260831-200044.zip`  
SHA-256: `6b45bd782bd21a754fac5e38cb193a8974ce2fe51fd1d756f419342494a72b44`  
Sumber: SVN backend **r78617** (menggantikan paket `20260829-015438` yang
dibuat dari r78484 dan kini usang).

## 0. Yang TIDAK perlu dipasang di server

Matcher wajah AIS (`AIS_COSINE_FACE_V1`) adalah **Java murni** — cosine
similarity atas embedding float32. Server **tidak** membutuhkan ONNX Runtime,
OpenCV, Python, CUDA/GPU, atau berkas model apa pun: embedding dihitung di
perangkat kasir, server hanya menyimpan ciphertext AES-256-GCM dan
mencocokkan angka. Fingerprint kelak butuh `AIS_BIOMETRIC_MATCHER_CLASS` +
JAR SDK vendor — gate terpisah yang masih ditunda.

## 1. Prasyarat OS

Tidak ada paket OS baru khusus biometrik selain stack AIS normal (JDK +
Tomcat + database yang sudah menjalankan `Api_eBisnis`). Satu tambahan yang
disarankan:

```bash
sudo apt install -y chrony && sudo systemctl enable --now chrony
```

Alasannya spesifik: **bukti verifikasi biometrik berumur <= 5 menit**. Jam
server yang melenceng dari jam kasir membuat checkout wajah ditolak
"kedaluwarsa" padahal baru direkam.

## 2. Isi paket dan cara memasang

Verifikasi hash sebelum ekstrak:

```bash
sha256sum ais-biometric-backend-20260831-200044.zip
```

Isi bundle (`WEB-INF/classes/...`):

- `PosApi` + inner class
- `BiometricApi`, `GerbangPesantrenApi` + inner class
- **`KantinHelper` + inner class** — helper POS yang dipanggil PosApi;
  memuat **validasi barcode unik per toko** (lihat §4). Sebelum 31 Agustus
  2026 kelas ini tidak pernah ikut bundle sehingga perbaikan di dalamnya
  tidak pernah ter-deploy; script packaging sudah diperbaiki.
- primitive crypto/matcher biometrik
- entity `BiometricCredential`, `BiometricEvent`, `IzinGerbangPesantren`
- `HIBERNATE_CHANGES.txt`, `MANIFEST.txt`, `SHA256SUMS.txt`

Langkah: cadangkan database + `WEB-INF/classes` server, lalu salin isi
`WEB-INF/classes` bundle ke aplikasi. **Jangan** menimpa `hibernate.cfg.xml`
server (bundle sengaja tidak membawanya — bisa memuat kredensial).

## 3. Skema database

Entitas biometrik dibuat otomatis Hibernate saat boot **bila**
`hbm2ddl.auto=update` aktif dan ketiga `<mapping class=...>` ada di
`hibernate.cfg.xml` server (daftarnya di `HIBERNATE_CHANGES.txt`). Verifikasi
nilai itu di server — jangan berasumsi sama dengan workstation. **Backup
database sebelum boot pertama pasca-deploy.**

## 4. Environment variable

Buat kunci master di server (jangan pernah lewat chat/log/tiket):

```bash
openssl rand -base64 32
```

Pasang di environment proses Tomcat — `setenv.sh` (tarball) atau
`systemctl edit tomcat` (service):

```
export AIS_BIOMETRIC_MASTER_KEY_BASE64='<hasil openssl>'
export AIS_BIOMETRIC_KEY_VERSION='1'
# Opsional; default 0.82 sudah lulus UAT Desktop:
# export AIS_BIOMETRIC_FACE_THRESHOLD='0.82'
# export AIS_BIOMETRIC_LIVENESS_THRESHOLD='<ambang>'
# HANYA untuk fingerprint (wajah TIDAK butuh):
# export AIS_BIOMETRIC_MATCHER_CLASS='<kelas provider SDK vendor>'
```

Berkas berisi kunci wajib `chmod 600`. **Simpan salinan kunci di secret
manager/brankas**: kehilangan kunci = seluruh template terenkripsi tidak
terbaca selamanya, tidak ada jalan pulih.

## 5. Restart dan verifikasi

```bash
sudo systemctl restart tomcat
```

Panggil action `biometrik_kemampuan` dan pastikan `server_encryption_ready`,
`face_matcher_ready`, serta `boleh_enroll_pengguna_lain` (akun UAT) bernilai
true. Jangan lanjut bila salah satu false.

## 6. Yang ikut aktif setelah deployment ini

**Validasi barcode unik per toko** (`KantinHelper.produkSimpan`): menyimpan
produk dengan barcode yang sudah dipakai produk lain **di toko yang sama**
ditolak (status 91) dengan pesan yang menyebutkan bahwa barcode sama hanya
boleh dipakai toko berbeda. Klien versi lama pun ikut terlindungi karena
validasinya di server. Uji pasca-deploy: dua produk barcode sama di satu toko
-> ditolak; di dua toko berbeda -> boleh.

## 7. Operasional lanjutan

- **Backup rutin** kini mencakup tabel biometrik (kredensial terenkripsi +
  audit). Jangan pernah di-drop saat rollback — runbook rollback ada di
  handover 29 Agustus §13.
- Transport API sebaiknya HTTPS (reverse proxy + TLS).
- Rotasi kunci lewat `AIS_BIOMETRIC_KEY_VERSION` dengan prosedur rotasi,
  bukan mengganti kunci begitu saja.
