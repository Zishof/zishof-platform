# Rilis eBisnis POS v1.34.35 (build 198)

Tanggal rilis: 10 September 2026

Varian: **eBisnis**

Status: kandidat UAT internal

## Ringkasan

Rilis ini menyiapkan paket eBisnis terpisah untuk pelatihan operasional POS, pengadaan, dan laporan. Materi akuntansi, COA, jurnal, dan posting tidak dimasukkan ke skenario pelatihan ini karena data COA An Nahl belum siap. Paket dan kanal pembaruan eBisnis diverifikasi agar tidak mengambil artefak Al-Bahjah, Nahl, atau varian lainnya.

## Ruang lingkup operasional

- Penjualan pada POS/Kasir dengan metode pembayaran non-saldo/tunai dan saldo.
- Permintaan Pembelian (PR).
- Pemesanan Pembelian (PO) termin dan bukan termin.
- Penerimaan Barang/BAST.
- Penerimaan tagihan vendor.
- Pembayaran tagihan vendor.
- Laporan penjualan dan pembelian.
- Laporan margin per produk dan per kategori.
- Laporan laba kotor harian.
- Empat Laporan Omzet dengan penelusuran transaksi sumber.

## Empat Laporan Omzet

Laporan yang diverifikasi pada server live:

1. Transaksi Omzet.
2. Omzet Produk Non-Saldo/Tunai.
3. Omzet Produk Saldo.
4. Rekap Omzet.

Setiap angka atau baris interaktif dapat diklik untuk membuka popup **Asal Angka**. Popup menampilkan nota dan rincian transaksi penyusun sehingga angka laporan dapat ditelusuri kembali ke transaksi asal. Keempat laporan dapat diunduh dalam format PDF dan Excel/XLSX.

## Hasil UAT

| Pemeriksaan | Hasil |
|---|---:|
| API pengadaan PR, PO, BAST, tagihan, dan pembayaran | 5/5 lulus; masing-masing 100 dokumen |
| Laporan operasional dan PDF server | 12/12 lulus |
| Katalog Laporan Omzet | 4/4 lulus |
| API dan PDF Laporan Omzet | 4/4 lulus |
| Popup rincian transaksi Laporan Omzet | 6/6 lulus |
| Ekspor XLSX Laporan Omzet dibuka kembali | 4/4 lulus |
| Rekonsiliasi total Laporan Omzet | Rp212.590.000; selisih Rp0 |
| Integrasi layar Windows | 2/2 lulus |
| Seluruh pengujian aplikasi eBisnis | 851/851 lulus |
| Verifikasi profil dan kanal pembaruan eBisnis | 7/7 lulus |

Dataset live UAT mencakup 504 transaksi penjualan, 100 transaksi saldo tambahan pada 100 produk berbeda, 100 dokumen pada setiap tahap pengadaan, 452 baris penerimaan/faktur pembelian, 201 produk margin, serta 13 kategori margin. Seluruh screenshot yang dipakai pada manual menampilkan data, bukan grid kosong.

## Langkah UAT pada perangkat

1. Pastikan transaksi lokal yang akan dibandingkan sudah tersinkronkan.
2. Tutup aplikasi POS yang sedang berjalan.
3. Pasang paket eBisnis v1.34.35 (build 198).
4. Login, pilih Kantin Demo, lalu tekan **Sinkronkan**.
5. Buka menu **Laporan-Laporan** dan pilih kategori Omzet.
6. Jalankan Transaksi Omzet, Omzet Produk Non-Saldo/Tunai, Omzet Produk Saldo, dan Rekap Omzet pada periode yang sama.
7. Klik angka atau baris untuk memeriksa transaksi penyusunnya.
8. Uji tombol Excel dan PDF, kemudian buka kembali setiap file hasil ekspor.
9. Cocokkan total Transaksi Omzet dengan penjumlahan Non-Saldo dan Saldo serta Rekap Omzet. Selisih harus Rp0.

## Backend dan penandatanganan paket

Backend yang dibutuhkan oleh empat Laporan Omzet telah tersedia pada server live dan seluruh audit API dinyatakan lulus. Tidak diperlukan deploy server tambahan untuk skenario rilis ini; pengguna hanya perlu memperbarui aplikasi eBisnis.

Paket saat ini ditujukan untuk UAT internal. APK diizinkan memakai debug signing dan installer Windows belum memiliki tanda tangan Authenticode. Setelah UAT pengguna disetujui, paket produksi wajib ditandatangani menggunakan sertifikat resmi organisasi sebelum didistribusikan secara luas.

## Dokumentasi dan bukti

- Manual Word dan PDF berisi screenshot nyata beranotasi, penjelasan setiap anotasi, flowchart, use case, aliran data/ERD ringkas, panduan, matriks laporan, rekonsiliasi, troubleshooting, dan checklist training.
- Bukti mesin mencakup JSON UAT end-to-end, JSON audit Laporan Omzet, JSON pengujian XLSX, serta PDF keluaran server untuk empat Laporan Omzet.
- Paket bukti terpisah menyertakan screenshot sumber, screenshot beranotasi, diagram, dokumen, dan evidence agar dapat diaudit ulang.

## Catatan kompatibilitas

- Paket rilis hanya untuk varian eBisnis dan tidak boleh digabungkan dengan installer atau metadata pembaruan varian lain.
- Laporan berbasis akuntansi tidak termasuk ruang lingkup training ini.
- Perubahan server, master, hak akses, toko, atau periode data harus diikuti UAT ulang sebelum bukti ini dipakai sebagai dasar penerimaan berikutnya.
