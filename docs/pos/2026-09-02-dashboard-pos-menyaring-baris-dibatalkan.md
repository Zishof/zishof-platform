# 77. Dashboard POS Ikut Menyaring Baris Penjualan yang Dibatalkan

Tanggal: 2 September 2026  
Lanjutan: dok. 65–69 (konsistensi angka penjualan)  
Sifat: menutup sumber selisih terakhir yang ditemukan pada audit menyeluruh

## Konteks

Audit konsistensi angka sebelumnya menyelaraskan laporan web (dok. 65, 67),
Dashboard Stok (dok. 68), dan tujuh panel Ringkasan (dok. 69). Penyisiran
dilanjutkan ke seluruh kueri yang menyentuh `koperasi.pembelian`.

## Temuan

Empat kueri di `PosKantinAction` menghitung nilai/qty/grafik penjualan tanpa
menyaring kolom `aktif`, padahal laporan dan dashboard lain menyaringnya:

| Bagian dashboard POS | Yang dihitung |
| --- | --- |
| Kartu statistik (13 hari, now vs prev) | total, jumlah transaksi, qty |
| Donut penjualan per kategori (7 hari) | total per kategori |
| Sparkline penjualan harian | total, transaksi, qty per hari |
| Daftar transaksi terbaru | SUM qty & total per transaksi |

Variabel filter bersama (`cond`, `condA`) hanya berisi `AND toko = …`, tanpa
aktif. Akibatnya kartu dan grafik dashboard POS bisa lebih besar daripada laporan
untuk periode yang sama.

## Perbaikan

Filter `COALESCE(aktif,true)=true` (atau `a.aktif` untuk kueri ber-alias)
ditambahkan **langsung di keempat titik**, bukan ke variabel `cond`/`condA`
bersama — karena `cond` juga dipakai kueri `koperasi.produk WHERE aktif=true`,
dan menambahkan filter ke variabel bersama akan ambigu (aktif tabel yang mana)
serta berisiko menyentuh kueri produk.

Untuk daftar transaksi, filter dipasang di awal builder `w` pada
`riwayatSelectSql()`, sehingga qty/total per transaksi tidak lagi digelembungkan
baris yang dibatalkan — konsisten dengan Report Order.

## Bukti

`TesDashboardPos` menjalankan bentuk kueri hasil perbaikan **apa adanya** ke
basis data, fixture 1 penjualan sah (6.000) + 1 baris dibatalkan (300.000):
**6/6 lulus**.

| Pemeriksaan | Hasil |
| --- | --- |
| Kartu statistik total = penjualan sah | 6.000 |
| Bentuk lama memang menghitung baris batal | 306.000 |
| Kartu statistik qty | 2 (bukan 102) |
| Donut kategori | 6.000 |
| Sparkline harian | 6.000 |
| Daftar transaksi (SUM per transaksi) | 6.000 |

## Dashboard lain: diperiksa, sudah benar

- `DashboardKantinAction`: seluruh kueri item memakai `wherePembelian()` yang
  mengembalikan `p.aktif = true AND …`. Aman.
- `DashboardKepatuhanKantinAction`: satu-satunya kueri item memakai
  `WHERE p.aktif = true`. Aman.

## Penutup audit konsistensi angka penjualan

Dengan ini seluruh permukaan yang menghitung penjualan dari `koperasi.pembelian`
memakai aturan yang sama (kecualikan baris dibatalkan, pakai nilai final
`p.total`): laporan web (dok. 65/67), Dashboard Stok (dok. 68), panel Ringkasan
(dok. 69), dan dashboard POS (dok. 77). Angka antar-layar kini sepadan untuk
periode yang sama.
