# Al-Bahjah POS v1.33.49

- Seluruh angka rekonsiliasi pada **Laporan Transaksi > Transaksi Per Kasir** dapat diklik untuk membuka transaksi/sesi penyusun, lengkap dengan total tiap kolom, cetak PDF, dan unduh Excel.
- Keenam tab Laporan Transaksi memiliki **Preview**, **Atur Model**, dan ekspor **PDF / Excel / Word**. Model laporan dapat mengatur kolom, filter, grup, header/footer, kertas, orientasi, margin, huruf, angka, total, analisa, dan grafik.
- Cetak struk thermal panjang tidak lagi dipaksa menjadi halaman A4 297 mm. POS mengirim satu halaman roll dinamis hingga batas aman driver 3270 mm agar cutter baru bekerja setelah seluruh footer selesai.
- Dashboard mendukung tanggal acuan dan rekap tujuh hari; tampilan kartu/grafik lebih responsif dan sidebar Desktop dapat diringkas.
- Monitor mutasi stok menampilkan harga jual, harga beli, total jual, dan total beli berdasarkan snapshot transaksi bila tersedia.

Validasi: kompilasi backend Java 7, analisis file perubahan, dan seluruh tes Flutter.
