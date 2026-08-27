# Sinkronisasi Seluruh Tabel

Tanggal: 27 Agustus 2026

## Tujuan

Tab **Sistem → Riwayat Sinkronisasi → Sinkronisasi Seluruh Tabel** menjadi pusat audit data lokal perangkat. Daftar tabel dibaca langsung dari `sqlite_master`, sehingga tabel SQLite baru otomatis muncul tanpa perubahan UI.

Grid menampilkan:

- jumlah tabel dan record lokal;
- jumlah record server untuk tabel yang mempunyai pasangan API 1:1;
- jumlah kolom lokal;
- antrean `PENDING`, baris `GAGAL`, dan soft-delete lokal;
- waktu perubahan lokal terakhir;
- status validitas, kendala, dan tindakan yang dapat dilakukan pengguna.

## Aturan keselamatan wajib

Penemuan tabel bersifat dinamis, tetapi sinkronisasi tidak boleh generik. Tabel hanya boleh disinkronkan jika adapter resminya sudah mendefinisikan API, kunci unik/idempotensi, pemetaan kolom, lingkup tenant/toko, sumber data utama, aturan konflik, dan perlakuan penghapusan.

Tabel baru tetap langsung terlihat dengan status **Lokal / belum ada adapter**. Tombol sinkronnya tidak aktif dan UI menjelaskan konfigurasi yang masih harus dibuat. Aplikasi dilarang mengirim nama tabel atau SQL bebas ke server karena dapat melewati otorisasi dan merusak jurnal asli.

Adapter awal:

| Tabel lokal | Perilaku aman |
|---|---|
| `produk_cache` | Unduh katalog lengkap sesuai lingkup toko, validasi paging, lalu replace atomik. Cache lama dipertahankan jika unduhan tidak lengkap. |
| `anggota_cache` | Unduh seluruh member aktif secara bertahap melalui `anggota_sync_list`, lalu replace atomik agar baris yang sudah hilang/nonaktif ikut bersih tanpa merusak cache lama bila unduhan gagal. |
| `transaksi_pending` | Kirim jurnal transaksi memakai outbox resmi dan kode unik yang sama. |
| `outbox_master` | Kirim perubahan master melalui replay idempoten yang sudah ada. |
| `outbox_is` | Kirim antrean Inventory & Sales yang aksinya sudah diizinkan. |

Tabel konfigurasi perangkat, log, pemetaan ID, dan cache gabungan tidak memiliki pasangan server 1:1. Angka server ditampilkan sebagai **Tidak 1:1**, bukan nol, agar pengguna tidak menyimpulkan data hilang.

## Edukasi error kepada pengguna

Setiap kegagalan harus menyebutkan:

1. proses/tabel yang gagal;
2. apa yang terjadi (offline, ditolak server, paging tidak lengkap, atau adapter belum tersedia);
3. bahwa data lokal lama tetap aman bila memang tidak diubah;
4. tindakan mandiri: periksa internet/alamat server, buka **Log Error**, perbaiki konfigurasi yang disebut, lalu tekan **Periksa Ulang** atau **Sinkron Tabel**;
5. kapan harus meminta pengembang, yaitu ketika tabel belum memiliki adapter atau penolakan server berulang setelah konfigurasi diperbaiki.

Jangan menampilkan pesan seperti “gagal” saja. Jangan menyarankan pengguna menekan Sinkron/Muat Ulang berulang bila penolakan bisnis server membutuhkan perbaikan data atau konfigurasi.

## UAT wajib

1. Buka tab dan pastikan seluruh tabel SQLite tampil.
2. Tambahkan tabel uji melalui migrasi/test, muat ulang, dan pastikan tabel muncul otomatis sebagai belum memiliki adapter.
3. Saat online, pastikan jumlah server produk/member tampil; saat offline, tampil petunjuk koneksi dan data lokal tetap terlihat.
4. Buat antrean `PENDING`, `GAGAL`, dan soft-delete; pastikan KPI serta kolom grid bertambah sesuai keadaan.
5. Sinkronkan satu tabel dan pastikan hanya adapter itu yang berjalan.
6. Sinkronkan semua dan pastikan hasil per adapter ditampilkan, termasuk kegagalan parsial; kegagalan satu adapter tidak menyembunyikan hasil adapter lain.
7. Pastikan tabel lokal-only tidak mempunyai tombol sinkron aktif.
