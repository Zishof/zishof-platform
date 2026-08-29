# Rilis POS Desktop dan Android 1.34.06 — eBisnis, Al-Bahjah, dan Nahl

Tanggal: 29 Agustus 2026

Versi aplikasi: `1.34.06+169`

Varian: `ebisnis`, `albahjah`, `nahl`

Tag GitHub: `v1.34.06-build169`

## Ringkasan

- Sinkronisasi awal setelah instalasi/pembaruan menampilkan tabel yang sedang diproses, jumlah data, persentase, dan status setiap tahap.
- Sinkronisasi menjalankan maksimal lima pekerjaan paralel, berpindah otomatis ke tabel berikutnya, dan menyediakan tombol **Batalkan** yang aman.
- Tombol **Sinkronkan** pada header menjalankan sinkronisasi seluruh tabel yang didukung, termasuk antrean transaksi lokal, perubahan master, dan perintah Inventory & Sales.
- Sinkron katalog produk memiliki retry untuk halaman yang masih sibuk agar proses tidak berhenti pada 0% karena permintaan sebelumnya belum selesai.
- Pencarian produk lama pada Kulakan/Bulk Entry dapat memilih hasil berdasarkan nama, kode, atau barcode dan mengisi baris draft.
- Detail Kulakan dapat dimuat kembali dengan respons server yang sesuai.
- Menu Produksi, Pengiriman, dan MitraInap mempertahankan panel navigasi kiri serta header aplikasi saat submenu dibuka.
- Kesalahan skema Produksi menjelaskan bahwa masalah berada pada layanan/server, tindakan pengguna, dan informasi yang perlu dikirim kepada admin.
- Price Tag membedakan barcode Code 128 yang dapat dipindai dari nomor barcode berbentuk teks.
- Varian Nahl memakai identitas **TokoQu Al-Bahjah An Nahl**, logo TokoQu, dan nama installer khusus.

## UAT dan kompilasi

- Seluruh `528` pengujian aplikasi eBisnis/Al-Bahjah/Nahl lulus.
- Analisis penuh menemukan `0` error kompilasi. Terdapat `53` temuan lama di modul lain: `52` saran lint/depresiasi dan `1` warning cast tidak perlu.
- Ketiga build Windows release dan kompilasi installer Inno Setup berhasil dari snapshot source yang sama.
- Ketiga build APK Android berhasil dengan `versionName 1.34.06` dan `versionCode 169`.
- APK Android menggunakan sertifikat **Android Debug** atas persetujuan eksplisit untuk UAT internal; APK ini bukan artefak produksi/Play Store.
- Metadata `ProductVersion` ketiga installer adalah `1.34.06`.
- SHA-256 dihitung ulang dari artefak final.
- Seluruh installer berstatus Authenticode `NotSigned`; rilis ini ditujukan untuk distribusi internal/UAT seperti rilis sebelumnya.

## Artefak

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.06.exe` | 85.763.166 byte | `C2C53DC48EBC89FC7110DD4052E3B2A107F7C58E77D925C5DDC9F65C94A0F640` |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.06.exe` | 85.825.059 byte | `A7E9D7CCB26CA46E3A2322550198B1985F20D3478FF5EE5971D2458AE76AAB8A` |
| Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.06.exe` | 85.889.156 byte | `73F0338C95704EC30298BF355DDA019BF5A428290D13EFBC06A0892C1C7D4C25` |

| Varian Android | Package ID | APK Debug/UAT | Ukuran | SHA-256 |
|---|---|---|---:|---|
| eBisnis | `id.zishof.ebisnis` | `app-ebisnis-release.apk` | 188.903.665 byte | `FD2E1F07A0820CDCC41CDD6548BA696B594042DEE0774C3A09A9F00EB4518AF7` |
| Al-Bahjah | `id.zishof.ebisnis.albahjah` | `app-albahjah-release.apk` | 188.964.690 byte | `C89E1FE902D37CE7AAAF2DAD3964458FF8DF53930EF54412E1D53EA062FC59C8` |
| Nahl | `id.zishof.ebisnis.nahl` | `app-nahl-release.apk` | 188.429.035 byte | `33EC53A9A24944D994162B133352DF55DD2D51FE0AFD7743268DFC91B093D717` |

APK Nahl terverifikasi mempunyai label **TokoQu Al-Bahjah An Nahl** dan launcher icon TokoQu.

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.06/`

## UAT pengguna setelah pembaruan

> APK Android pada rilis ini khusus UAT internal. Jika perangkat sudah memiliki aplikasi dengan package ID sama tetapi sertifikat berbeda, Android akan menolak pembaruan langsung. Jangan menghapus aplikasi/data operasional sebelum memastikan transaksi pending sudah aman; gunakan signing produksi untuk rollout resmi.

1. Jangan menghapus database atau folder data lokal. Pastikan transaksi pending dicoba sinkron sebelum memasang pembaruan.
2. Pasang installer sesuai toko. Dialog penyiapan data lokal tetap berfokus pada pilihan aman **Nanti**, sehingga sinkronisasi penuh tidak berjalan tanpa persetujuan pengguna.
3. Bila koneksi stabil, pilih **Sinkronkan Sekarang**. Pastikan nama tabel, jumlah data, dan persentase bergerak. Aplikasi memproses maksimal lima tabel bersamaan dan otomatis mengambil tabel berikutnya.
4. Bila perlu menghentikan proses, tekan **Batalkan**. Data lokal yang sudah ada dipertahankan; jalankan ulang sinkronisasi ketika koneksi stabil.
5. Tombol **Sinkronkan** di header dapat digunakan kapan saja untuk sinkronisasi penuh, termasuk transaksi pending.
6. Untuk Price Tag yang dapat dipindai, aktifkan **Tampilkan Barcode (Bisa Dipindai)**. Opsi **Tampilkan Nomor Barcode Saja** hanya mencetak angka.
7. Pada varian Nahl, pastikan nama aplikasi/toko dan logo tampil sebagai **TokoQu Al-Bahjah An Nahl**.
8. Buka submenu Produksi dan Pengiriman. Panel kiri dan header harus tetap tersedia.

## Prasyarat backend Produksi

Kesalahan PostgreSQL `relation inventory_production.production_document does not exist` bukan kesalahan desktop dan tidak dapat diselesaikan dengan Muat Ulang berulang. Backend SVN r78572 mengubah seluruh endpoint Produksi agar mengembalikan kode `PRODUCTION_SCHEMA_NOT_READY` beserta edukasi pengguna dan tindakan admin, tanpa mencoba DDL saat request berjalan.

Admin server perlu:

1. memastikan namespace PostgreSQL `inventory_production` tersedia;
2. memperbarui source backend minimal ke SVN r78572;
3. me-restart aplikasi agar konfigurasi Hibernate membuat/memutakhirkan tabel yang dipetakan;
4. memverifikasi `inventory_production.production_document` tersedia sebelum UAT Produksi.

Aturan native SQL juga sudah diperketat pada SVN r78569-r78571: jangan memakai cast PostgreSQL `::TYPE` dalam query native Hibernate; gunakan `CAST(... AS TYPE)`.

Backend tidak dikemas menjadi WAR dalam proses rilis desktop ini sesuai arahan deployment terpisah oleh admin.

## Rollback

- Hentikan rollout bila aplikasi tidak dapat dibuka, sinkronisasi menyebabkan data lokal tidak dapat dibaca, atau fungsi kasir utama terganggu.
- Kembalikan desktop ke GitHub Release `v1.34.04-build162`.
- Rollback aplikasi tidak boleh disertai penghapusan database lokal, transaksi pending, atau outbox. Setelah versi lama terpasang, periksa **Sistem → Riwayat Sinkronisasi** dan kirim Detail Error kepada admin.
