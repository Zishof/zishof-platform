# Rilis UAT POS Al-Bahjah dan Nahl 1.34.27

Tanggal: 8 September 2026

Versi aplikasi: `1.34.27+190`

Backend SVN: `r88284`

## Perubahan

1. **Rekap Produk Terjual tidak lagi memisahkan produk yang sama.** Kode
   transaksi/snapshot seperti `EB...-AN000820` dinormalisasi ke kode produk
   kanonis `AN000820`. Kuantitas, jumlah transaksi, dan total penjualan produk
   yang sama kini dijumlahkan dalam satu baris.
2. **Bulk Entry Faktur Kulakan menampilkan TOTAL HPP tepat setelah PPN.** Rumus
   per baris adalah `Qty × Harga Beli − Diskon + PPN`. Kolom HPP Unit tetap
   tersedia agar nilai total dan nilai satuan dapat dibandingkan.
3. **Excel Penerimaan per Kasir berisi rincian per nota.** Filter tanggal,
   kasir, dan metode pembayaran tetap dihormati. Untuk kebutuhan tunai, pilih
   metode **Tunai** lalu tekan **Excel**. File memuat tanggal, waktu, nota,
   kasir, pembeli, metode, qty, total nota, dan penerimaan metode.
4. **Pembayaran split dihitung sesuai porsinya.** Contoh nota QRIS + Tunai tetap
   menampilkan total nota penuh, tetapi kolom Penerimaan Metode hanya memuat
   bagian Tunai ketika filter Tunai dipilih.
5. **Rincian lebih dari 100 nota tidak terpotong.** Endpoint rincian penerimaan
   sekarang mendukung paginasi melalui backend SVN `r88284`.

## Cara UAT ekspor Tunai

1. Buka **Laporan Transaksi → Penerimaan per Kasir**.
2. Tentukan tanggal dan kasir yang akan diperiksa.
3. Pilih **Metode Bayar: Tunai**, kemudian tekan **Terapkan**.
4. Cocokkan jumlah transaksi dan total pada tabel/popup rincian.
5. Tekan tombol **Excel** pada bagian atas.
6. Pastikan setiap nota menjadi satu baris dan jumlah kolom **Penerimaan
   Metode** sama dengan total Tunai pada filter aktif.

## Verifikasi otomatis

- 35 pengujian Flutter terkait ekspor penerimaan, rekap produk, paginasi
  rincian, Total HPP, dan regresi persetujuan harga lulus.
- Analisis statis Flutter pada kode dan pengujian terkait: tidak ada masalah.
- `PosApi.java` dengan perubahan paginasi berhasil dikompilasi memakai Java 8.

Catatan: paket UAT Android dapat menggunakan debug signing dan installer
Windows dapat berupa paket unsigned. Gunakan paket produksi bertanda tangan
untuk distribusi final di luar UAT internal.
