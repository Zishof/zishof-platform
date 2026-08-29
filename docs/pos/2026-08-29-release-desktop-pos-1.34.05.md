# Rilis Desktop POS 1.34.05 — eBisnis, Al-Bahjah, dan Nahl

Tanggal: 29 Agustus 2026

Versi aplikasi: `1.34.05+168`

Varian: `ebisnis`, `albahjah`, `nahl`

Tag GitHub: `v1.34.05-build168`

## Ringkasan

- Sinkronisasi awal setelah instalasi/pembaruan menampilkan tabel yang sedang diproses, jumlah data, persentase, dan status setiap tahap.
- Sinkronisasi menjalankan maksimal lima pekerjaan paralel, berpindah otomatis ke tabel berikutnya setelah satu pekerjaan selesai, dan menyediakan tombol **Batalkan** yang aman.
- Tombol **Sinkronkan** pada header menjalankan sinkronisasi seluruh tabel yang didukung, termasuk antrean transaksi lokal, perubahan master, dan perintah Inventory & Sales.
- Sinkron katalog produk memiliki retry untuk halaman yang masih sibuk agar proses tidak berhenti pada 0% karena permintaan sebelumnya belum selesai.
- Menu Produksi, Pengiriman, dan MitraInap mempertahankan panel navigasi kiri serta header aplikasi saat submenu dibuka.
- Kesalahan skema Produksi sekarang menjelaskan bahwa masalah berada pada layanan/server, tindakan yang dapat dilakukan pengguna, dan informasi yang perlu dikirim kepada admin.
- Opsi Price Tag diperjelas: **Tampilkan Barcode (Bisa Dipindai)** mencetak barcode Code 128 beserta angkanya, sedangkan **Tampilkan Nomor Barcode Saja** hanya mencetak teks dan tidak dapat dipindai.

## UAT dan kompilasi

- Seluruh `527` pengujian aplikasi eBisnis/Al-Bahjah/Nahl lulus.
- Analisis penuh menemukan `0` error kompilasi. Terdapat `53` temuan lama di modul lain: `52` saran lint/depresiasi dan `1` warning cast tidak perlu.
- Ketiga build Windows release dan kompilasi installer Inno Setup berhasil dari snapshot source yang sama.
- SHA-256 dihitung ulang setelah build dan cocok dengan berkas checksum yang dibuat oleh pipeline.
- Seluruh installer berstatus Authenticode `NotSigned`; rilis ini ditujukan untuk distribusi internal/UAT seperti rilis sebelumnya.

## Artefak

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.05.exe` | 85.595.067 byte | `2D3333E5EAE347A67B900ABFCC7CEBE3FDB6456DBE2FBC42603D16F94664C788` |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.05.exe` | 85.645.565 byte | `0EE59E600BBA752251B50339B88C4BF9546FAF936274BABAC055E570208A3BE5` |
| Nahl | `FF-Fajrul-Falah-Mart-Setup-1.34.05.exe` | 85.597.328 byte | `9C5709C1E37FCCD70CE13204C15AA1856B9C175D075C1A0F94D9D13535015A3E` |

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.05/`

## UAT pengguna setelah pembaruan

1. Pastikan transaksi pending sudah dicoba sinkron sebelum memasang pembaruan. Jangan menghapus database atau folder data lokal.
2. Pasang installer sesuai toko. Saat aplikasi menawarkan penyiapan data lokal, pilihan awal tetap **Nanti** agar sinkronisasi tidak berjalan tanpa persetujuan pengguna.
3. Bila koneksi stabil, pilih **Sinkronkan Sekarang**. Pastikan nama tabel, jumlah data, dan persentase bergerak. Aplikasi memproses maksimal lima tabel bersamaan dan otomatis mengambil tabel berikutnya.
4. Bila perlu menghentikan proses, tekan **Batalkan**. Data lokal yang sudah ada dipertahankan; jalankan ulang sinkronisasi ketika koneksi stabil.
5. Tombol **Sinkronkan** di header dapat digunakan kapan saja untuk sinkronisasi penuh, termasuk transaksi pending.
6. Untuk Price Tag yang dapat dipindai, aktifkan **Tampilkan Barcode (Bisa Dipindai)**. Jangan hanya mengaktifkan **Tampilkan Nomor Barcode Saja** karena opsi itu mencetak angka tanpa garis barcode.
7. Buka beberapa submenu Produksi dan Pengiriman. Panel kiri dan header harus tetap tersedia.

## Batasan backend yang masih perlu admin

Rilis desktop ini memperbaiki navigasi serta edukasi kesalahan, tetapi tidak membuat tabel Produksi di database server. Bila menu Produksi menampilkan pesan bahwa skema atau tabel belum tersedia, memuat ulang berulang kali tidak menyelesaikannya. Pengguna dapat melanjutkan menu POS lain, lalu mengirim nama menu, waktu kejadian, toko, dan Detail Error kepada admin. Admin perlu menuntaskan deployment skema/backend yang sesuai sebelum data Produksi dapat dimuat.

## Rollback

- Hentikan rollout bila aplikasi tidak dapat dibuka, sinkronisasi menyebabkan data lokal tidak dapat dibaca, atau fungsi kasir utama terganggu.
- Kembalikan desktop ke GitHub Release `v1.34.04-build162`.
- Rollback aplikasi tidak boleh disertai penghapusan database lokal, transaksi pending, atau outbox. Setelah versi lama terpasang, periksa **Sistem → Riwayat Sinkronisasi** dan kirim Detail Error kepada admin.
