# HANDOVER AI — Local-First POS, Biometrik, dan ePesantren

Tanggal handover: **29 Agustus 2026 (Asia/Jakarta)**  
Komputer kerja: komputer Windows yang sama dengan semua jalur absolut di bawah  
Audiens: AI/Codex sesi berikutnya yang akan melanjutkan implementasi, pengujian, deployment, dan rilis

## 1. Tujuan dan cara memakai handover ini

Dokumen ini adalah sumber awal operasional untuk melanjutkan pekerjaan lintas tiga codebase:

1. POS Desktop/Android Flutter di `C:\opt\CodeBaseDesktopDanMobile`.
2. Backend AIS Java/ZK/JSP di `C:\opt\AIS\ais\src\main\src` (SVN).
3. eCampus/eSchool/ePesantren Flutter di `C:\opt\mobileAis\ais_mobile`.

AI berikutnya **wajib membaca dokumen ini seluruhnya**, lalu memeriksa ulang status Git/SVN dan source aktual sebelum mengubah file. Percakapan sebelumnya sangat panjang dan beberapa sesi AI pernah bekerja paralel. Source lokal dan status version control adalah bukti utama; jangan menganggap seluruh perubahan lokal berasal dari satu sesi.

Prinsip utama yang tidak boleh diubah:

> Semua proses CRUD yang aman untuk offline harus memakai **Local-First**: baca lokal lebih dahulu, tulis lokal lebih dahulu, tampilkan hasil segera, lalu sinkronkan ke server secara idempoten di background. Server tetap sumber kebenaran akhir dan penolakan bisnis tidak boleh dianggap sukses lokal permanen.

## 2. Status codebase saat handover

### 2.1 POS Flutter

- Root: `C:\opt\CodeBaseDesktopDanMobile`
- Aplikasi: `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis`
- Branch: `main`
- Commit HEAD saat handover: `b899ed6 docs(pos): catat UAT deploy dan rollback r78486`
- Versi `pubspec.yaml`: `1.34.03+161`
- Kondisi: **dirty working tree**; jangan reset, checkout, clean, stash, atau menimpa perubahan tanpa audit.

Perubahan POS yang tampak terkait biometrik saat handover antara lain:

- `apps/ebisnis/android/app/src/main/kotlin/id/zishof/ebisnis/MainActivity.kt`
- `apps/ebisnis/lib/api_client.dart`
- `apps/ebisnis/lib/screens/anggota/member_biometric_panel.dart`
- `apps/ebisnis/lib/screens/keranjang_screen.dart`
- `apps/ebisnis/lib/services/biometric_capture_bridge.dart`
- `apps/ebisnis/lib/widgets/app_drawer.dart`
- `apps/ebisnis/lib/widgets/app_shell.dart`
- test biometrik dan layout terkait
- script build/release dan dokumentasi readiness

Ada perubahan **Pengiriman** dari pekerjaan/sesi lain. Jangan dicampur ke commit biometrik kecuali pengguna secara eksplisit meminta:

- `apps/ebisnis/lib/screens/pengiriman_screen.dart`
- `apps/ebisnis/test/pengiriman_menu_contract_test.dart`
- `docs/pos/2026-08-28-implementasi-menu-pengiriman-desktop-android.md`

### 2.2 Backend AIS

- Working copy SVN yang benar: `C:\opt\AIS\ais\src\main\src`
- Revision saat handover: **r78487**
- Status saat diperiksa: **bersih** (`svn status` tidak menghasilkan perubahan).
- Jangan membuat repository Git di backend ini; backend dikelola dengan SVN.
- Konfigurasi Hibernate yang digunakan selama pengembangan mengandalkan `hbm2ddl.auto=update` untuk penambahan tabel/kolom yang sudah dipetakan. Verifikasi konfigurasi server sebelum deployment; jangan berasumsi server memakai file konfigurasi lokal.

### 2.3 eCampus/eSchool/ePesantren Flutter

- Root: `C:\opt\mobileAis\ais_mobile`
- Branch: `feat/app-wide-offline-first`
- Commit HEAD saat handover: `44ddbb67 docs(pembayaran): inventaris fungsi ZK Fase C + status per menu`
- Versi `pubspec.yaml`: `2.5.15+1220260827`
- Kondisi: **dirty working tree** dengan perubahan lokal dan artefak build.
- Jangan menyentuh `android/key.properties` atau menyalin password signing ke source/log/dokumen.

## 3. Aturan kerja wajib untuk AI berikutnya

### 3.1 Perlindungan perubahan lokal

1. Jalankan `git status --short` atau `svn status` sebelum mengedit.
2. Audit diff per file sebelum memodifikasi file yang sudah berubah.
3. Jangan menjalankan `git reset --hard`, `git checkout --`, `git clean`, atau penghapusan rekursif.
4. Jangan menggabungkan perubahan antarfitur dalam satu commit.
5. Jangan commit/push/publish tanpa instruksi eksplisit pengguna pada turn aktif.
6. Backend hanya di-commit dengan SVN setelah compile dan test relevan lulus.

### 3.2 Secret dan data sensitif

Jangan menulis atau mencetak:

- password pengguna/UAT;
- token login/API;
- password keystore;
- private key;
- template fingerprint atau embedding wajah mentah;
- `AIS_BIOMETRIC_MASTER_KEY_BASE64`;
- data pribadi hasil UAT.

Gunakan environment variable. Laporan readiness hanya boleh memuat status tersedia/tidak, bukan nilainya.

### 3.3 Local-First adalah kontrak arsitektur

Setiap CRUD baru harus diklasifikasikan:

- **cached read**: render snapshot lokal dahulu, fetch server di background, diff berdasarkan ID stabil, simpan snapshot server ke lokal, animasikan tambah/ubah/hapus;
- **queueable mutation**: simpan optimistic row/draft lokal, enqueue command dengan ID idempoten, tampilkan status lokal, kirim background, lalu konfirmasi/rekonsiliasi;
- **online-only**: autentikasi, otorisasi sensitif, pembayaran/posting final yang belum diaudit, penghapusan berisiko, dan operasi yang bergantung stok/saldo real-time.

Jangan pernah mengantre semua POST secara buta. Di AIS banyak endpoint baca juga memakai POST.

## 4. Kontrak Local-First yang harus dipertahankan

### 4.1 Alur baca

```text
Buka layar
  -> baca cache lokal
  -> render segera + label "data tersimpan"
  -> request server di background
  -> validasi respons lengkap/berhalaman
  -> diff per primary key stabil
  -> upsert data baru/berubah ke lokal
  -> hapus lokal hanya jika server benar-benar authoritative dan lengkap
  -> animasikan row baru/berubah/hapus
  -> perbarui timestamp cache
```

Jangan menghapus cache berdasarkan satu halaman respons pagination. Bug lama pernah membuat puluhan row lokal dianggap dihapus karena halaman server diperlakukan sebagai snapshot lengkap.

### 4.2 Alur simpan

```text
Klik Simpan
  -> validasi lokal
  -> tulis row/draft lokal dalam transaksi DB
  -> enqueue outbox + clientMutationId/idempotency key
  -> tampilkan "Tersimpan di perangkat"
  -> tutup form tanpa menunggu jaringan
  -> background flush
  -> server menerima tepat sekali atau me-replay respons dedup
  -> tandai row tersinkron + animasi sukses
  -> jika penolakan bisnis: tandai GAGAL/CONFLICT dan minta keputusan pengguna
```

Retry transport boleh memakai exponential backoff; permintaan pengguna sebelumnya menyebut pemeriksaan sekitar lima menit. Jangan retry penolakan bisnis berkode tanpa perubahan payload/keputusan pengguna.

### 4.3 Data minimum outbox

- local event ID;
- action/method/path;
- payload terenkripsi bila mengandung data sensitif;
- `clientMutationId`/idempotency key;
- entity key;
- status (`PENDING`, `SENDING`, `FAILED`, `COMPLETED`, `DEAD_LETTER`);
- attempts;
- next attempt time;
- last error yang sudah disanitasi;
- created/updated time;
- server reference bila berhasil.

### 4.4 Konflik

- Gunakan version/updated-at dari server bila tersedia.
- Jangan silently overwrite perubahan server yang lebih baru.
- Tampilkan before/after untuk konflik penting.
- Operasi saldo, stok, jurnal, approval, dan transaksi final tetap divalidasi ulang server.

## 5. Pekerjaan POS yang sudah dilakukan dalam rangkaian diskusi

Bagian ini merangkum pekerjaan historis. Karena working tree masih dirty, AI berikutnya harus mengaitkan tiap butir dengan source/test aktual sebelum menyatakan selesai atau membuat rilis.

### 5.1 Infrastruktur Local-First POS

- `MasterOffline` untuk master data dengan cache lokal, outbox, retry, indikator global, dan optimistic overlay.
- Database lokal `core_db`/SQLite untuk cache referensi, member, produk, transaksi pending, outbox master, outbox Inventory & Sales, dan log error.
- `DiffDaftarLokal` dan `KilauBaris` untuk menandai row baru/berubah setelah refresh server.
- Perbaikan respons daftar agar field top-level seperti `summary`, `ringkasan`, dan total pagination tidak hilang.
- Perlindungan agar pagination tidak menghapus row lokal yang belum tercakup halaman server.
- Indikator status simpan lokal, sedang sinkron, terkirim, dan gagal.
- Dedup/idempotency backend untuk mutation ApiEBisnis.

### 5.2 CRUD dan laporan

Pola Local-First telah diperluas ke banyak master dan laporan, termasuk anggota, jenis/tipe anggota, produk/jenis/grup produk, supplier, cara bayar, toko, diskon, role, mutasi, topup, pesanan, laporan, dan sebagian riwayat transaksi. Jangan mengklaim “semua CRUD” hanya berdasarkan nama; lakukan audit source-kontrak berikut:

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
rg "ApiClient\.instance\.aksi" lib\screens
rg "MasterOffline\.(daftarCacheDulu|simpanAtauAntre)" lib\screens
rg "KilauBaris|DiffDaftarLokal" lib\screens
```

Untuk operasi transaksi finansial, gunakan outbox khusus transaksi dan validasi idempoten—bukan outbox master generik.

### 5.3 Member, PIN, limit, dan cara bayar

Diskusi dan implementasi mencakup:

- PIN member dan pengelolaan supervisor;
- upload/download PIN dengan pembatasan hak akses;
- aturan wajib PIN pada Jenis Anggota dan Tipe Anggota;
- pemilihan metode pembayaran yang diizinkan dan metode default;
- opsi mengunci kasir agar tidak memilih cara bayar lain;
- batas transaksi harian/mingguan/bulanan;
- pengajuan melebihi limit dan persetujuan role tertentu;
- cakupan aturan semua toko atau toko terpilih;
- opsi aturan PIN per metode pembayaran;
- validasi ulang server sebelum pembayaran.

Area ini pernah mengalami bug: UI menampilkan semua cara bayar walaupun tipe member terkunci, dan transaksi dapat lolos tanpa PIN. Jangan hanya menguji widget; UAT wajib membuktikan server menolak payload yang tidak memenuhi aturan.

### 5.4 Produk dan transaksi

- Sinkron produk server-lokal.
- Dukungan stok minus berdasarkan kebijakan toko.
- kartu KPI produk yang clickable dan dialog detail berpagination;
- PDF/Excel untuk daftar produk;
- rekonsiliasi transaksi lokal ↔ server;
- identifikasi transaksi hanya-lokal, hanya-server, nominal berbeda, dan duplikat;
- detail transaksi harus menggunakan ID server yang valid, tidak boleh mengirim `id:null`;
- penghapusan transaksi lokal yang tidak ada di server harus eksplisit, terkonfirmasi, dan tidak menghapus outbox yang masih layak retry;
- scanner barcode/QR melalui kamera HP dan webcam Desktop sedang/baru dikembangkan; audit implementasi aktual sebelum rilis.

### 5.5 Varian dan branding

- Varian `nahl` untuk POS Desktop/Android.
- Judul varian Nahl diminta menjadi **FF (Fajrul Falah) Mart**.
- Logo Al-Bahjah An-Nahl disediakan pengguna dan pernah dimasukkan ke alur build.
- Varian Al-Bahjah dan Nahl pernah beberapa kali dibangun/dirilis; versi historis jangan dianggap latest. Gunakan versi `pubspec.yaml` aktual dan verifikasi tag GitHub sebelum publish baru.

## 6. Implementasi biometrik yang sudah selesai di sisi software

### 6.1 Fitur

- Enrollment maksimum **5 slot fingerprint** dan **5 slot wajah** per member/subjek.
- Panel pengelolaan biometrik member di Flutter.
- Kamera/webcam untuk capture wajah.
- Bridge fingerprint eksternal; Desktop memiliki adapter SecuGen WebAPI melalui loopback HTTPS port `8000`.
- Android harus memakai scanner eksternal USB/OTG + SDK vendor untuk fingerprint member.
- Verifikasi biometrik checkout bersifat fail-closed ketika aturan mewajibkan biometrik.
- Penyimpanan server terenkripsi AES-256-GCM.
- Event/audit biometrik.
- Face matcher/provider abstraction.
- Fingerprint matcher/provider abstraction untuk template ISO/vendor.

Catatan teknis yang tidak boleh dilanggar:

> Fingerprint bawaan Android tidak dapat membaca atau mengekspor template sidik jari orang/member lain ke server. `BiometricPrompt` hanya mengautentikasi pengguna perangkat. Verifikasi member terhadap data AIS memerlukan scanner eksternal USB/OTG dan SDK vendor.

### 6.2 API backend biometrik

Action yang telah dibuat/didaftarkan:

- `biometrik_kemampuan`
- `biometrik_daftar`
- `biometrik_simpan`
- `biometrik_nonaktifkan`
- `verifikasi_biometrik_member`

Entitas penting:

- `BiometricCredential`
- `BiometricEvent`
- `IzinGerbangPesantren`

Self-test backend berada di package test biometrik dan sudah masuk SVN r78487.

### 6.3 Konfigurasi environment produksi

Nama environment yang relevan (jangan tulis nilainya ke dokumen/log):

- `AIS_BIOMETRIC_MASTER_KEY_BASE64`
- `AIS_BIOMETRIC_KEY_VERSION`
- `AIS_BIOMETRIC_MATCHER_CLASS`
- threshold/provider matcher terkait
- `AIS_BIOMETRIC_API_URL`
- `AIS_BIOMETRIC_UAT_TOKEN`
- variable signing Android dan allowlist sertifikat Windows

### 6.4 Hal yang belum dapat diselesaikan hanya dengan source

- Scanner fingerprint fisik belum terpasang/terdeteksi pada mesin audit.
- SecuGen WebAPI/SgiBioSrv belum berjalan pada port 8000.
- SDK dan lisensi vendor scanner belum tersedia.
- Provider fingerprint produksi belum dapat diuji dengan template nyata.
- Face embedding dan liveness production provider perlu dipastikan di server.
- Secret master biometrik server belum tersedia di environment lokal.
- UAT fisik enrollment → match → checkout belum dapat dijalankan.
- Signing produksi Android/Windows belum lengkap pada audit terakhir.

Jangan memalsukan kelulusan gate-gate tersebut.

## 7. ePesantren/eCampus/eSchool yang telah dibahas/dikerjakan

Rangkaian diskusi mencakup:

- V3 UI/UX e-Learning, shell responsif, period picker, course workspace, dashboard peserta/pengajar, kalender, autosave tugas, timer ujian server-aware, dan golden test;
- offline cache/outbox AES-GCM dan coordinator;
- dashboard nilai mahasiswa dan endpoint agregat kehadiran;
- Pustaka dan Repository read-only berbasis API, tanpa iframe/webview, dengan watermark identitas pembaca per halaman;
- permission Pustaka/Repository per `Tbmrole`, bukan per pengguna;
- landing page `pesantren.jsp` yang customizable dari JSON `Yayasan.website`;
- branding/build varian Nahl dan ePesantren An-Nahl;
- menu entry biometrik, absensi biometrik, serta izin keluar-masuk pondok untuk admin/keamanan;
- lokalisasi Bahasa Indonesia berdasarkan data pengguna;
- dokumen konsep/presentasi ePesantren dan workflow operasional.

Karena `ais_mobile` masih dirty, audit setiap fitur terhadap source dan test aktual. Jangan mengulang pekerjaan yang sudah selesai dan jangan mencampur perubahan lokal pengguna.

## 8. Bukti verifikasi terakhir

### 8.1 Flutter POS

Perintah:

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
C:\opt\flutter\bin\flutter.bat test --no-pub
```

Hasil terakhir:

- **442/442 test lulus**.
- Test terarah biometrik/PIN: **18/18 lulus**.
- Targeted analyzer empat file biometrik: **No issues found**.
- Full analyzer: tidak ada error kompilasi; terdapat 53 issue lint lama (52 info dan 1 warning `unnecessary_cast` pada laporan), di luar perubahan biometrik terarah.

### 8.2 Backend

- Java compile paket biometrik berhasil.
- `BiometricCoreSelfTest: OK`.
- SVN bersih pada r78487 saat handover.

### 8.3 Paket backend biometrik

Paket terakhir:

`C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\release-artifacts\biometric-backend\ais-biometric-backend-20260829-015438.zip`

SHA-256:

`9ED565AFC4626E254510AB943BA03965DC6F4AA49EA677496A114188009BB24B`

Paket sudah diperiksa agar tidak membawa source Java, konfigurasi Hibernate, `.env`, properties rahasia, JDBC string, atau perubahan Pengiriman.

### 8.4 Readiness lokal

Laporan:

`C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\release-artifacts\biometric-backend\readiness-local-20260829.json`

Hasil:

- kamera Desktop: PASS, dua perangkat terdeteksi;
- SecuGen WebAPI: FAIL, port 8000 belum aktif;
- API UAT biometrik: FAIL, URL/token environment belum disediakan.

## 9. Script operasional yang tersedia

- `apps/ebisnis/tool/check_biometric_readiness.ps1`
- `apps/ebisnis/tool/package_biometric_backend.ps1`
- `apps/ebisnis/tool/verify_apk_signing.ps1`
- `apps/ebisnis/tool/verify_windows_signing.ps1`
- `apps/ebisnis/tool/build_apk_nahl.ps1`
- `apps/ebisnis/tool/build_windows_nahl.ps1`
- script build Al-Bahjah dan semua varian lain di folder yang sama

Dokumentasi readiness:

`C:\opt\CodeBaseDesktopDanMobile\docs\pos\2026-08-29-kesiapan-produksi-biometrik-pos.md`

## 10. Langkah pertama sesi AI berikutnya

Jalankan pemeriksaan ini, tanpa mengubah file:

```powershell
# POS
Set-Location C:\opt\CodeBaseDesktopDanMobile
git status --short
git branch --show-current
git log -1 --oneline
git diff --stat

# Backend AIS
Set-Location C:\opt\AIS\ais\src\main\src
svn status
svn info --show-item revision

# ePesantren/eCampus/eSchool
Set-Location C:\opt\mobileAis\ais_mobile
git status --short
git branch --show-current
git log -1 --oneline
```

Kemudian baca:

```powershell
Get-Content -Raw C:\opt\CodeBaseDesktopDanMobile\docs\pos\HANDOVER_AI_LOCAL_FIRST_BIOMETRIK_EPESANTREN_2026-08-29.md
Get-Content -Raw C:\opt\CodeBaseDesktopDanMobile\docs\pos\2026-08-29-kesiapan-produksi-biometrik-pos.md
Get-Content -Raw C:\opt\CodeBaseDesktopDanMobile\docs\pos\2026-08-26-verifikasi-biometrik-pembayaran-saldo.md
```

## 11. Perintah untuk melanjutkan pekerjaan teknis

### 11.1 Verifikasi software POS

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
C:\opt\flutter\bin\flutter.bat pub get
C:\opt\flutter\bin\flutter.bat test --no-pub
C:\opt\flutter\bin\flutter.bat analyze --no-pub `
  lib\services\biometric_capture_bridge.dart `
  lib\screens\anggota\member_biometric_panel.dart `
  test\member_biometric_enrollment_contract_test.dart `
  test\biometric_saldo_member_test.dart
```

### 11.2 Buat ulang paket backend

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
.\tool\package_biometric_backend.ps1
```

Catatan: audit script sebelum menjalankan bila revision backend sudah berubah. Jangan tanpa sengaja memasukkan fitur Pengiriman atau file konfigurasi server.

### 11.3 Readiness aman tanpa mencetak secret

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
.\tool\check_biometric_readiness.ps1 `
  -ReportPath .\release-artifacts\biometric-backend\readiness-latest.json
```

Untuk UAT server, pengguna harus memasang environment URL/token sendiri. Jangan meminta token ditempel ke chat atau command history.

### 11.4 UAT fisik biometrik minimum

1. Pastikan driver scanner dan SecuGen WebAPI aktif.
2. Jalankan readiness sampai semua provider yang diperlukan PASS.
3. Login dengan akun UAT yang memiliki izin enrollment.
4. Enrollment 5 slot fingerprint dan 5 slot wajah pada subjek uji yang berizin.
5. Tutup/buka aplikasi; pastikan metadata slot tetap tersedia dari server/cache.
6. Uji match benar, jari/wajah salah, spoof/liveness gagal, timeout, scanner dicabut, dan offline.
7. Aktifkan aturan biometrik pada jenis/tipe member.
8. Pastikan checkout tanpa bukti biometrik ditolak server.
9. Pastikan checkout dengan bukti valid hanya terposting sekali walaupun request diulang.
10. Periksa audit event tanpa mengekspos template biometrik.

## 12. Acceptance criteria sebelum deployment/rilis

### Backend

- SVN source bersih atau diff teridentifikasi.
- Compile Java lulus.
- Self-test biometrik lulus.
- mapping Hibernate tersedia.
- master encryption key tersedia melalui environment.
- matcher provider dan threshold produksi terkonfigurasi.
- endpoint kemampuan melaporkan readiness yang benar.
- rollback bundle dan backup database tersedia.

### Flutter

- test terarah dan full test lulus.
- tidak ada error analyzer pada file yang disentuh.
- Local-First tidak menghapus cache karena pagination.
- outbox idempoten dan error bisnis tidak di-retry buta.
- kamera/webcam/scanner menampilkan kegagalan yang jelas.
- checkout biometrik fail-closed.

### Release

- versi dinaikkan;
- APK release signed dengan sertifikat produksi, bukan Android Debug;
- installer Windows signed dengan sertifikat allowlist;
- SHA-256 dibuat;
- release notes jujur mencantumkan fitur yang belum UAT fisik;
- tag/release GitHub diverifikasi setelah upload;
- auto-update menunjuk release/channel yang benar.

## 13. Rollback

Jika deployment backend biometrik bermasalah:

1. Hentikan traffic/fitur enrollment baru.
2. Pertahankan tabel biometrik; jangan drop karena berisi audit/credential terenkripsi.
3. Kembalikan class/JAR/route ke bundle server sebelumnya.
4. Restart/reload aplikasi server sesuai runbook lokal.
5. Verifikasi endpoint login dan POS lama.
6. Nonaktifkan aturan wajib biometrik sementara melalui konfigurasi role/member yang tersedia.
7. Simpan log request ID yang sudah disanitasi.

Jika aplikasi POS bermasalah, rollback ke release signed sebelumnya. Jangan menghapus database lokal sebelum mengekspor outbox pending dan transaksi lokal yang belum terkirim.

## 14. Prompt siap-tempel untuk AI sesi berikutnya

Salin pesan berikut ke sesi AI baru:

```text
Baca seluruh file:
C:\opt\CodeBaseDesktopDanMobile\docs\pos\HANDOVER_AI_LOCAL_FIRST_BIOMETRIK_EPESANTREN_2026-08-29.md

Lanjutkan pekerjaan pada komputer ini. Jangan mulai dari nol dan jangan mengulang pekerjaan yang sudah lulus verifikasi. Audit lebih dahulu status Git di C:\opt\CodeBaseDesktopDanMobile dan C:\opt\mobileAis\ais_mobile, serta status SVN di C:\opt\AIS\ais\src\main\src. Working tree memiliki perubahan milik pengguna/sesi lain; jangan reset, clean, checkout, stash, atau mencampur fitur Pengiriman.

Pertahankan konsep Local-First untuk seluruh CRUD yang aman: baca cache lokal dahulu, tulis lokal dahulu, outbox idempoten, background sync, diff animatif untuk tambah/ubah/hapus, dan server sebagai sumber kebenaran akhir. Jangan blanket-queue semua POST dan jangan menganggap penolakan bisnis sebagai sukses.

Prioritas lanjutan:
1. Verifikasi kembali diff biometrik POS dan jangan menyentuh perubahan Pengiriman.
2. Jalankan full test, targeted analyzer, backend compile/self-test, dan readiness script.
3. Lakukan UAT fisik fingerprint/wajah hanya setelah scanner, SDK/vendor matcher, server secret, URL/token UAT, dan izin pengguna tersedia.
4. Audit sisa CRUD yang masih memanggil ApiClient langsung dan klasifikasikan cached-read, queueable-mutation, atau online-only.
5. Jangan commit/push/publish kecuali saya meminta secara eksplisit.

Laporkan bukti konkret, blocker eksternal, file yang berubah, dan hasil test. Jangan menulis secret, password, token, data pribadi, atau template biometrik ke source/log/dokumen.
```

## 15. Definisi selesai yang jujur

Sisi software dapat disebut selesai ketika source, test, compile, packaging, dan readiness checks lulus. Sistem biometrik **belum boleh disebut siap produksi end-to-end** sampai perangkat fisik, SDK vendor, provider matcher/liveness, key server, signing produksi, dan UAT lapangan benar-benar lulus dengan bukti.

Handover ini tidak melakukan commit, push, publish, deployment, atau perubahan database. Dokumen ini hanya menyiapkan kelanjutan kerja yang aman dan dapat diaudit.
