# Rilis Desktop POS 1.34.10 — eBisnis, Al-Bahjah, dan TokoQu An-Nahl

Tanggal: 30 Agustus 2026  
Versi aplikasi: `1.34.10+172`  
Varian: `ebisnis`, `albahjah`, `nahl`  
Tag GitHub: `v1.34.10`  
Prasyarat backend: SVN `r78605`

## Ringkasan perubahan

- Hasil stok opname langsung memperbarui stok lokal pada perangkat yang melakukan pencatatan.
- Server mengembalikan stok akhir otoritatif sehingga angka fisik, katalog Produk, dan Kasir/POS tidak lagi memakai snapshot lama.
- Perangkat kasir lain mengambil perubahan stok opname melalui feed ringan berkala sekitar setiap 15 detik tanpa perlu mengunduh ulang seluruh katalog produk.
- Layar Produk dan Kasir/POS mendengarkan perubahan cache stok yang sama sehingga angka stok diperbarui konsisten.
- Jika koneksi server terputus, hasil stok opname tetap dicatat secara local-first dan dikirim ulang melalui antrean sinkronisasi.
- Admin atau supervisor dapat membatalkan stok opname yang salah. Pembatalan membuat jurnal kompensasi dan mempertahankan jurnal asli sebagai jejak audit.
- Endpoint backend `so_perubahan_stok` dan `so_batalkan` tersedia mulai SVN `r78605`.

## Verifikasi sebelum rilis

- `40` pengujian terarah untuk local-first, retry, sinkronisasi stok, dan pagination lulus.
- Analisis terarah tidak menemukan error atau warning baru; empat lint informasi baseline pada `core_db` tetap ada.
- `git diff --check` lulus.
- Ketiga aplikasi Windows berhasil dikompilasi ulang dari source tree bersama dan installer Inno Setup terbentuk.
- Ketiga installer berstatus Authenticode `NotSigned`; distribusi ini ditujukan untuk operasional internal/UAT.
- SHA-256 dihitung ulang dari artefak final dan cocok dengan berkas checksum pendamping.

## Artefak Desktop Windows

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.10.exe` | 85.807.682 byte | `40A680F7B06CB29A324DBF3E8625CB850779A97430E20C80B7E26F1AC71C5504` |
| Al-Bahjah POS | `Al-Bahjah-POS-Setup-1.34.10.exe` | 85.880.794 byte | `3874FC7CF90B011C26FE9DF05586B07CF07D3FE4655D295065D666956D5DA98B` |
| TokoQu Al-Bahjah An-Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.10.exe` | 85.949.754 byte | `A8054528E577BC1041CE06E025A31B60FD54950E94AC87B207566002120620F9` |

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.10/`

## Urutan pemasangan

1. Pastikan backend SVN `r78605` sudah selesai dibangun, Tomcat sudah memuat WAR baru, dan endpoint POS kembali sehat.
2. Jangan menghapus database lokal, transaksi pending, outbox, atau cache aplikasi lama.
3. Pasang installer sesuai varian dan pastikan versi di kiri bawah menunjukkan `1.34.10`.
4. Tekan Sinkronkan satu kali setelah login bila perangkat baru selesai diperbarui.

## UAT stok opname

1. Pilih satu produk uji dan catat stok awalnya pada Produk dan Kasir/POS.
2. Masukkan stok fisik baru melalui Stok Opname.
3. Pastikan perangkat pencatat langsung menampilkan stok akhir yang sama.
4. Pada kasir lain yang online, tunggu sekitar 15–30 detik lalu pastikan Produk dan Kasir/POS menampilkan angka yang sama tanpa muat ulang katalog penuh.
5. Pastikan server juga menyimpan stok akhir yang sama.
6. Uji satu entri salah menggunakan akun admin/supervisor, batalkan stok opname tersebut, isi alasan, dan pastikan jurnal kompensasi terbentuk serta stok kembali benar.
7. Bila status masih menunggu kirim, jangan input ulang. Buka Sistem > Riwayat Sinkronisasi dan biarkan aplikasi mengirim ulang setelah server dapat dihubungi.

## Rollback

- Hentikan pemakaian versi baru bila aplikasi tidak dapat dibuka, database lokal tidak dapat dibaca, atau alur transaksi terganggu.
- Kembali ke GitHub Release `v1.34.09` untuk aplikasi Desktop.
- Rollback backend memakai artefak WAR sebelum SVN `r78605` bila endpoint stok opname baru menyebabkan gangguan.
- Jangan menghapus database lokal, transaksi pending, outbox master, jurnal stok opname, atau cache foto saat rollback.
