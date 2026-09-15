# Al-Bahjah POS 1.34.39 build 202 — Release

Status GitHub: Release biasa (bukan Pre-release), hanya untuk varian Al-Bahjah.
Pada 16 September 2026 status publikasi diubah atas permintaan pengguna;
berkas APK/installer tidak berubah. Pengujian tetap lokal, APK memakai debug
signing, installer unsigned, tanpa ZIP auto-update, dan backend tetap lokal.
Perubahan label publikasi bukan pengesahan UAT produksi atau pemulihan data toko.

## Cakupan aplikasi

- Menahan pengakuan sinkron dan pencetakan apabila total server tidak cocok
  dengan rincian transaksi lokal. Tidak mencampurkan grand total nota lain.
- Mempertahankan transaksi lokal yang gagal/berkonflik untuk pemeriksaan;
  salinan checkout asli tidak ditimpa oleh replikasi server.
- Memberi sufiks acak pada nomor struk untuk mengurangi bentrok antarperangkat.
- Membaca saldo resmi setelah pembayaran terkonfirmasi; saldo yang belum
  terverifikasi tidak dicetak sebagai saldo pasti.
- Memperjelas konflik kasir/perangkat dan akses pemeriksaan antrean tertahan;
  identitas perangkat dimuat secara serial agar stabil.
- Memperjelas galat login ketika server mengembalikan HTML, bukan JSON API.
- Mempertahankan perbaikan Kulakan, ekspor global, filter tipe member Topup,
  serta aturan stempel LUNAS dari kandidat 1.34.38.

## Pemisahan varian

- Al-Bahjah memakai tag `albahjah-*`, Nahl memakai `nahl-*`.
- Aset APK, EXE, dan ZIP harus cocok dengan varian; ZIP Nahl yang namanya
  memuat Al-Bahjah juga ditolak kanal Al-Bahjah.
- Folder sementara unduhan dan helper Windows unik per pemasangan sehingga
  versi bernomor sama tidak saling menimpa paket/helper.
- Installer hanya memasukkan executable Al-Bahjah; AppId dan direktori
  instalasi berbeda dari Nahl.
- Updater baru tidak menawarkan draft/prerelease secara otomatis. Karena
  rilis ini sekarang berstatus Release biasa, updater kanal Al-Bahjah dapat
  menawarkannya sesuai versi terpasang. Rilis tetap tanpa ZIP auto-update
  dan tidak dijadikan GitHub latest; kanal Nahl tetap memakai tag `nahl-*`.
- Rilis dan aset Nahl tidak boleh diedit atau diganti saat publikasi ini.

## Batasan wajib disampaikan

Ini bukan bukti bahwa seluruh masalah operasional toko sudah selesai.
Backend koreksi pembayaran dan validasi replay masih berupa patch lokal,
belum dipasang di server toko. Transaksi historis, dua antrean tertahan,
saldo riil, dan sesi kas tidak diubah melalui pekerjaan ini. Pemetaan toko
akun finance/admin serta master tipe member Yayasan perlu verifikasi PIC.

APK memakai sertifikat debug seperti kandidat sebelumnya; installer Windows
unsigned. Label GitHub adalah Release biasa, tetapi paket belum memakai
sertifikat produksi dan pengujian tetap terbatas pada lingkungan lokal.

Jika pengujian menemukan data lokal hilang, perpindahan varian, atau struk
tidak konsisten tetap bisa dicetak, hentikan penggunaan kandidat dan simpan
bukti serta backup lokal. Jangan menghapus antrean, uninstall, atau menimpa
saldo untuk menyamarkan masalah. Pemulihan versi/data perlu dilakukan bersama
PIC setelah backup dan rekonsiliasi, bukan melalui update otomatis kandidat ini.

## Verifikasi

Tanggal pemeriksaan: 16 September 2026. Source aplikasi:
`d248ad1ada4e1caa146256fe2024535f4618bed8`.

Ringkasan cakupan laporan pengguna:

| Laporan | Bukti lokal dan batasannya |
| --- | --- |
| Total/rincian struk berbeda dan riwayat lokal tertimpa | Tes integritas ACK, snapshot struk, outbox, riwayat, dan database lulus; data historis server belum direkonsiliasi. |
| Dua transaksi tertahan atau konflik kas | Status gagal/antrean dan identitas perangkat diperbaiki; tidak ada penutupan paksa atau penghapusan antrean toko. |
| Saldo voucher dan koreksi metode pembayaran | Aplikasi tidak mengklaim saldo yang belum terverifikasi; patch koreksi backend hanya dikompilasi lokal, belum diuji dengan ledger produksi. |
| Kulakan berbeda antar-akun/rincian tidak terbuka | Tes lingkup tenant/toko dan kontrak detail lulus; hak akses/pemetaan akun riil belum diperiksa. |
| Unduh Kulakan global, filter member, stempel LUNAS | Tes ekspor lintas halaman, parameter/filter tipe member, serta klasifikasi pelunasan lulus. |
| Input member baru/tipe Yayasan tidak muncul | Tidak menginput atau mengubah master member produksi; perlu verifikasi data/hak akses PIC. |
| Login Nahl menerima HTML | Penanganan respons non-JSON diperjelas; tidak ada login live atau publikasi paket Nahl. |
| Nahl ter-update menjadi Al-Bahjah | Tes pemisahan kanal, aset, installer, dan updater Nahl lama lulus; rilis hanya aset Al-Bahjah tanpa ZIP. |

- `core_update`: 15/15 lulus, termasuk menjalankan updater asli Nahl 1.34.37
  dari tag `nahl-v1.34.37-wa-uat-20260914` (commit
  `f5088949323a800f8df116524bb5c574b22900a3`) terhadap rilis Al-Bahjah lebih baru.
- `core_db`: 14/14 lulus.
- Identitas/kanal Nahl dan installer: 4/4 lulus.
- Analisis helper updater dan tes installer: tidak ada masalah.
- Suite aplikasi Al-Bahjah final: **897/897 lulus**.
  Pada percobaan awal satu tes gagal dengan galat shader tidak ditemukan;
  saat itu beberapa proses tes/build berjalan bersamaan. Uji terarah ulang 9/9 dan
  suite lengkap ulang lulus; tidak ada pengujian yang dilewati/dihapus.
- Backend lokal `KantinHelper.java`: kompilasi Java 17 berhasil; bukan UAT
  transaksi database dan bukan deployment backend.
- APK berhasil dibangun dan diverifikasi: paket `id.zishof.ebisnis.albahjah`,
  label Al-Bahjah POS, versi `1.34.39`, versionCode `202`.
- Sertifikat debug APK sama dengan APK Al-Bahjah 1.34.38 sebelumnya:
  SHA-256 `455a25a1353cb4bce4777017e50ea55f7e251f402aad50832da4fb438163b9d9`.
  Ini memverifikasi kesamaan penandatanganan kedua berkas, bukan bukti bahwa
  seluruh instalasi di lapangan memakai sertifikat yang sama.
- Pengujian di atas adalah tes otomatis lokal, bukan UAT langsung pada akun
  toko atau bukti cetak dari perangkat kasir/printer fisik.
- Build Windows berhasil. Metadata executable: Al-Bahjah POS `1.34.39+202`;
  metadata installer: Al-Bahjah POS `1.34.39`, status unsigned/UAT.
- Snapshot aplikasi Windows yang dikemas identik dengan hasil kompilasi baru.
- Kompilasi native barcode menghasilkan peringatan konversi angka/variabel
  tak terpakai, tetapi build APK dan Windows selesai dengan exit code 0.

## Unduhan dan checksum

[Halaman rilis Al-Bahjah](https://github.com/Zishof/zishof-platform/releases/tag/albahjah-v1.34.39-local-uat-20260916)

- [APK Al-Bahjah — debug signing](https://github.com/Zishof/zishof-platform/releases/download/albahjah-v1.34.39-local-uat-20260916/app-albahjah-release.apk)
  (191.194.047 byte). SHA-256:
  `fac679e7284496b80ac7dcc35f8d43b63cd13083a05c30e96bc26bf76bca399a`.
- [Installer Windows Al-Bahjah — unsigned](https://github.com/Zishof/zishof-platform/releases/download/albahjah-v1.34.39-local-uat-20260916/Al-Bahjah-POS-Setup-1.34.39.exe)
  (86.065.985 byte). SHA-256:
  `9256f2aaf0ce14d4a5169f35e1ea4ca7aa11d91695e5de17082a430d376b353b`.

Kedua berkas disertai `.sha256.txt`. Tidak ada ZIP auto-update dan tidak ada
paket Nahl dalam rilis ini. Rilis tidak ditetapkan sebagai GitHub latest.
