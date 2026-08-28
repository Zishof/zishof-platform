# Diagnostik tombol Edit Transaksi

Tanggal: 28 Agustus 2026

Tombol **Edit Transaksi** pada **Riwayat Penjualan > Detail** hanya muncul bila
seluruh gerbang berikut terpenuhi:

1. kebijakan global aktif, atau kebijakan toko aktif;
2. akun adalah admin global, supervisor toko, atau grup pengguna berizin
   Supervisor; dan
3. baris yang dibuka mempunyai header transaksi kelompok, bukan hanya rincian
   penjualan tunggal.

Pada **Konfigurasi > Identitas Mesin**, tulisan **NONAKTIF GLOBAL — keputusan
mengikuti konfigurasi toko aktif** berarti sakelar global belum mengizinkan
edit. Dalam keadaan itu admin harus membuka **Konfigurasi > Profil Toko >
Keamanan & Koreksi Transaksi Toko**, mengaktifkan izin untuk toko yang sedang
dipilih, lalu menekan **Simpan Profil Toko**. Alternatifnya, admin global dapat
mengaktifkan kebijakan global pada tab Identitas Mesin untuk seluruh toko.

Sesudah perubahan, tekan **Sinkronkan**, **Muat Ulang**, lalu buka kembali
detail transaksi. Bila detail yang dibuka adalah baris rincian lama, pilih
baris **Order ... (kode transaksi)** yang mempunyai kode sama. Aplikasi kini
menampilkan alasan spesifik di dalam dialog ketika tombol Edit tidak tersedia,
sehingga pengguna tidak perlu menebak gerbang mana yang belum terpenuhi.
