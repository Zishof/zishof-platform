# 67. Konsistensi Angka Laporan, Satuan Jual, dan Filter Lanjutan

Tanggal: 2 September 2026  
Lanjutan: dok. 64 (rincian produk), dok. 65 (perbaikan laporan web tahap 1)  
Cakupan: tujuh butir lanjutan yang disepakati pemilik

## 1. Dasar perhitungan omzet: nilai final baris, bukan hitung ulang

Laporan web menghitung omzet sebagai `hargasatuan × qty − diskon`, sedangkan POS
memakai `p.total` — nilai FINAL yang benar-benar ditagihkan dan disimpan kasir,
termasuk hasil **harga grosir**, **harga Pack**, dan pembulatan.

Untuk penjualan biasa keduanya sama. Pada baris berharga grosir hasilnya
menyimpang: nota pelanggan menyebut satu angka, laporan web menyebut angka lain.
Kini `OMZET` memakai `coalesce(p.total, rumus lama)` — baris lama yang belum
menyimpan `total` tetap dihitung dengan rumus sebelumnya sehingga laporan periode
lampau tidak berubah menjadi nol.

Bukti: fixture menjual 12 Pcs dengan harga satuan 5.000 tetapi nilai final
55.000 (harga grosir). Laporan menampilkan **55.000**, bukan 60.000.

## 2. Penjualan produk terhapus tidak lagi hilang dari 13 kueri

Dok. 65 memperbaiki dua laporan rincian. Tiga belas kueri lain — termasuk
Penjualan per Barang, Barang Paling Laku, Margin Produk, Slow Moving, Analisa
Diskon, dan Kontribusi Produk — masih memakai `INNER JOIN` ke master produk,
sehingga penjualan produk yang sudah dihapus **hilang tanpa jejak** dan totalnya
lebih kecil daripada penjualan sebenarnya.

Seluruhnya kini `LEFT JOIN`, dan enam laporan yang mengelompokkan per produk
memakai label yang jatuh ke kode/nama snapshot pada baris penjualan.

## 3. Label satuan jual di laporan web

Aplikasi kasir menampilkan "1 Lusin (12 Pcs)"; laporan web hanya menampilkan
angka dasar "12". Dua laporan rincian kini memiliki kolom **Satuan** (satuan
dasar) dan **Satuan Jual** (mis. "1 Lusin", kosong bila dijual per satuan dasar),
sehingga laporan web dan aplikasi dapat diadu tanpa salah tafsir.

## 4. Batas pengujian tab (dikerjakan sebagian, disebutkan apa adanya)

Uji widget yang merender Laporan Transaksi sungguhan terbukti **rapuh**: layar
memanggil API saat init, dan di lingkungan uji panggilan itu meninggalkan timer
yang membuat kerangka uji menyatakan kegagalan secara tidak menentu. Menstabilkannya
menuntut `ApiClient` yang dapat disuntik, sedangkan `ApiClient.instance` saat ini
`static final` — merombaknya menyentuh seluruh aplikasi dan tidak pantas
dilakukan sepihak di tengah pekerjaan laporan.

Yang dikerjakan sebagai gantinya: uji unit atas kontrak yang paling mudah salah —
aturan berhenti halaman, perangkuman rekap, dan penanda hasil terpotong. Refactor
injeksi `ApiClient` dicatat sebagai pekerjaan tersendiri bila pemilik menghendaki
uji tingkat layar.

## 5. Rentang tanggal bawaan

Tab Rincian Produk kini terbuka dengan rentang **hari ini**. Sebelumnya tab
membuka seluruh riwayat toko; pada laporan tingkat item itu berarti puluhan ribu
baris hanya untuk menampilkan halaman pertama. Pengguna tetap bebas melebarkan
rentangnya.

## 6. Ekspor yang tidak lengkap kini menyatakan dirinya

Pengambil halaman berhenti pada batas pengaman 1.000 halaman. Sebelumnya batas
itu tersentuh tanpa suara. Kini hasil pengambilan membawa penanda `terpotong`,
yang memunculkan peringatan di layar dan catatan **"SEBAGIAN: data melebihi batas
unduhan"** pada subjudul PDF/Excel/Word. Laporan yang diam-diam terpotong lebih
berbahaya daripada laporan yang gagal — angkanya terlihat wajar dan tetap
dipakai.

## 7. Filter kasir pada laporan web

`qKasir` ditambahkan pada empat laporan penjualan (Penjualan per Barang, Barang
Paling Laku, Rincian Penjualan per Barang, Detail Transaksi Penjualan), lengkap
dengan kolom isian **Cari Kasir** di layar Laporan. Kolom itu hanya tampil pada
laporan yang benar-benar menyaring per kasir — daftarnya dipusatkan di
`LaporanKatalogData.LAPORAN_BERFILTER_KASIR`, karena kolom filter yang tampil
pada laporan yang mengabaikannya membuat pengguna menyaring dan mengira hasilnya
sudah terfilter.

Dua laporan yang sebelumnya tidak menjoin header nota kini memakai `LEFT JOIN`
ke header, sehingga baris tanpa header tidak ikut hilang saat filter tidak
dipakai.

## Bukti

| Uji | Hasil |
| --- | --- |
| `TesLaporanWeb` (17 skenario: omzet final, produk terhapus, kasir, satuan jual, filter kasir) | 17/17 |
| `TesRincianProduk` | 18/18 |
| `rekap_produk_test`, `rincian_produk_halaman_test`, `rincian_produk_terpotong_test` | 16/16 |
| `flutter analyze` | bersih |

## Yang masih menunggu

Perbaikan sisi server berlaku setelah build dipasang ke ebisnis.id dan Tomcat
di-restart. Perubahan aplikasi menuntut rilis; APK produksi masih menunggu
keystore (lihat dok. 66).
