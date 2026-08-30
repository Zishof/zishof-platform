# Rilis Desktop POS 1.34.09 — eBisnis dan TokoQu An-Nahl

Tanggal: 30 Agustus 2026  
Versi aplikasi: `1.34.09+171`  
Varian: `ebisnis`, `nahl`  
Tag GitHub: `v1.34.09`

## Ringkasan perubahan

- Foto produk dari server maupun antrean local-first tetap dipulihkan saat form edit dibuka kembali.
- Kartu produk Kasir/POS menampilkan foto produk; bila tersedia lebih dari satu foto, gambar berganti otomatis setiap tiga detik.
- Riwayat Penjualan menerima pencarian transaksi melalui pemindaian barcode/QR struk, termasuk kode mentah, URL, dan payload JSON yang memuat nomor transaksi.
- Price Tag menyediakan label produk `50 x 18 mm`, ukuran stiker dan kertas kustom, orientasi potret/landscape, margin tepi, serta jarak antarkotak.
- Perhitungan grid preview dan PDF memakai fungsi yang sama. Preset label `50 x 18 mm` pada A4 potret menghasilkan tiga kolom.
- Cache dan outbox media menyimpan identitas foto server bersama salinan lokal sehingga gangguan endpoint media tidak menghilangkan preview.
- Seluruh perubahan yang berada di working tree bersama pada saat build ikut dikompilasi ke kedua varian.

## Verifikasi sebelum rilis

- Seluruh `567/567` pengujian Flutter lulus.
- Analisis penuh menemukan `0` error kompilasi. Masih terdapat `53` diagnostik baseline: `52` info dan `1` warning cast tidak perlu.
- `git diff --check` lulus.
- Kedua installer Windows berhasil dibangun sebagai release dan mempunyai `ProductVersion 1.34.09`.
- Kedua installer berstatus Authenticode `NotSigned`; distribusi ini ditujukan untuk operasional internal/UAT.
- SHA-256 dihitung ulang dari artefak final dan cocok dengan berkas checksum pendamping.

## Artefak Desktop Windows

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.09.exe` | 85.808.836 byte | `351F31668281B2EA900F2D2DECAF9D0B5ECD9796BC39A3C04C602362918E9833` |
| TokoQu An-Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.09.exe` | 85.932.138 byte | `62BEAB0F9CF5E464F04A5C05991812B7B5F24389864022143B806495F1205B72` |

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.09/`

## UAT pengguna setelah pembaruan

1. Pastikan transaksi pending sudah diperiksa. Jangan menghapus database atau data aplikasi lama.
2. Pasang installer sesuai varian, lalu pastikan versi di kiri bawah menunjukkan `1.34.09`.
3. Buka Produk, edit produk yang mempunyai foto, dan pastikan preview tampil kembali.
4. Buka Kasir/POS dan pastikan foto produk tampil. Produk dengan beberapa foto harus berganti gambar setiap tiga detik.
5. Buka Riwayat Penjualan, pindai barcode/QR struk, lalu pastikan transaksi yang sesuai ditemukan.
6. Buka Price Tag, pilih label `50 x 18 mm`, periksa preview tiga kolom pada A4 potret, kemudian lakukan satu uji cetak sebelum mencetak massal.
7. Bila data berstatus tersimpan di perangkat tetapi belum terkirim, buka Sistem > Riwayat Sinkronisasi. Jangan input ulang; aplikasi akan mencoba pengiriman kembali.

## Rollback

- Hentikan pemakaian versi baru bila aplikasi tidak dapat dibuka, database lokal tidak dapat dibaca, atau alur Kasir/POS terganggu.
- Kembali ke GitHub Release `v1.34.08`.
- Jangan menghapus database lokal, transaksi pending, outbox master, atau cache foto saat rollback.
