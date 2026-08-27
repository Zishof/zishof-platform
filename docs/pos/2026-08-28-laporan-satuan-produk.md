# Kelengkapan Satuan/UOM pada Laporan Produk

Tanggal: 28 Agustus 2026

## Masalah

Kolom **Satuan** sudah ada pada laporan/ekspor produk, tetapi produk lama yang `produk.satuan`-nya belum diatur menghasilkan sel kosong. Sel kosong sulit dibedakan antara data master yang belum lengkap dan kegagalan ekspor.

Satuan tidak boleh ditebak dari nama produk, barcode, kategori, atau stok. Nama seperti `250 ML`, `40 GR`, atau `BOTOL` belum membuktikan unit transaksi yang benar; menebaknya dapat merusak penilaian stok dan harga per unit.

## Aturan perbaikan

- Bila master satuan tersedia, tampilkan nama satuan sebenarnya.
- Bila satuan null atau namanya kosong, tampilkan **(Belum diatur)**.
- Pola yang sama berlaku untuk pemasok utama pada ekspor Daftar Barang dan Jasa.
- Ekspor **Daftar Barang dan Jasa** memiliki sheet **Ringkasan Kelengkapan** berisi total produk, satuan sudah/belum diatur, dan pemasok belum diatur.
- Placeholder **(Belum diatur)** dinormalisasi kembali menjadi kosong saat file diimpor. Aplikasi dilarang membuat master satuan atau pemasok bernama `(Belum diatur)`.
- Jangan mengubah data produk secara otomatis hanya untuk membuat laporan terlihat lengkap.

## Cakupan laporan yang diselaraskan

1. Daftar Barang dan Jasa / ekspor katalog Excel.
2. Daftar Barang dan Jasa pada mesin laporan bersama.
3. Stok Barang per Tanggal.
4. Persediaan & Kartu Stok, termasuk PDF dan Excel.
5. Daftar Harga Jual / Analisis Harga, termasuk PDF dan Excel.
6. Ekspor Excel dari layar tinjau impor produk.

## Tindakan pengguna

1. Unduh ulang **Daftar Barang dan Jasa**.
2. Buka sheet **Ringkasan Kelengkapan** untuk melihat jumlah satuan yang belum diatur.
3. Pada sheet utama, filter kolom **Satuan** dengan nilai `(Belum diatur)`.
4. Isi satuan yang benar melalui form **Produk → Ubah → Satuan**, atau isi kolom Satuan di Excel kemudian gunakan **Impor Produk**.
5. Unduh ulang laporan untuk memastikan jumlah **Satuan belum diatur** menjadi nol.

## UAT

- Satuan null diekspor sebagai `(Belum diatur)`.
- Satuan `Pcs` tetap diekspor sebagai `Pcs`.
- Placeholder hasil ekspor diimpor kembali sebagai nilai kosong dan tidak membuat master baru.
- Satuan yang dikoreksi pengguna, misalnya `Kg`, tetap diterima.
- Empat class laporan/export terkait berhasil dikompilasi dengan Java 8.
