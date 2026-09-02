# 69. Panel Ringkasan Ikut Menyaring Baris Penjualan yang Dibatalkan

Tanggal: 2 September 2026  
Lanjutan: dok. 65, 67, 68 (konsistensi angka laporan)

## Masalah

Setelah laporan web dan Dashboard Stok diselaraskan, penyisiran atas seluruh
kueri yang menyentuh `koperasi.pembelian` menemukan sumber selisih ketiga:
**tujuh panel Ringkasan** menghitung angka penjualan tanpa menyaring kolom
`aktif`, sedangkan laporan dan POS menyaringnya.

| Panel | Kueri terdampak |
| --- | --- |
| Analisis Laba | 1 |
| Forecast | 3 |
| Leaderboard | 1 |
| Jam Sibuk (peak hour) | 2 |
| Produk Terlaris | 2 |
| Pelanggan Terloyal | 1 |
| Rekap Produk Terlaris | 1 |

Akibatnya angka pada Ringkasan bisa lebih besar daripada Laporan untuk periode
yang sama — selisih tanpa penjelasan yang merusak kepercayaan pada **kedua**
layar sekaligus, bukan hanya salah satunya.

## Cara memperbaiki, dan alasannya

Filter dipasang **di sumber** lewat subquery ber-alias:

```sql
FROM (SELECT * FROM koperasi.pembelian WHERE COALESCE(aktif,true)=true) a
```

bukan dengan menambal tiap klausa `WHERE`. Bentuk `WHERE` pada berkas-berkas ini
berbeda-beda dan sebagian dirakit dari potongan JavaScript (`filterTokoSQL`,
`filterWaktuSQL`, `filterPencarianSQL`), sehingga menambal satu per satu mudah
terlewat sekarang dan mudah rusak lagi saat seseorang menyunting kuerinya nanti.
Dengan filter di sumber, setiap kueri yang membaca alias itu otomatis bersih.

PostgreSQL meratakan (*pull-up*) subquery sesederhana ini, jadi rencana kueri dan
pemakaian indeksnya tidak berubah.

## Bukti

`TesPanelRingkasan` menjalankan bentuk kueri hasil perbaikan **apa adanya** ke
basis data, dengan fixture satu penjualan sah (12.000) dan satu baris dibatalkan
(300.000): **5/5 lulus**.

| Pemeriksaan | Hasil |
| --- | --- |
| Panel terlaris hanya menghitung penjualan sah | 12.000 |
| Bentuk lama memang ikut menghitung baris dibatalkan | 312.000 |
| Bentuk join (toko + produk) tetap sah dan tersaring | 12.000 |
| Kolom tanpa alias tetap terbaca dari subquery | 1 baris |
| Agregat sederhana tersaring | 12.000 |

## Catatan yang perlu diketahui pemilik

Kueri pada panel-panel ini **ditulis di sisi klien** (JavaScript) lalu dikirim ke
endpoint data generik. Perbaikan ini tidak mengubah rancangan tersebut — hanya
memperbaiki angkanya. Rancangan itu sendiri layak ditinjau tersendiri, karena
kueri yang dirakit di klien menyulitkan penjaminan bahwa setiap layar memakai
aturan penyaringan yang sama; itu justru akar dari cacat yang ditemukan di sini
dan pantas menjadi keputusan tersendiri, bukan sisipan.
