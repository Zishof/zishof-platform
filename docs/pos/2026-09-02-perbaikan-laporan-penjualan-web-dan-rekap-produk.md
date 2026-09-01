# 65. Perbaikan Laporan Penjualan Web, Filter, dan Rekap Produk

Tanggal: 2 September 2026  
Lanjutan: dok. 64 (rincian produk terjual) — permintaan An Nahl 1 September 2026  
Cakupan: enam butir yang disepakati pemilik (laporan web, filter, saklar UOM,
rekap produk, uji ekspor, rilis)

## 1. Laporan penjualan web: tiga cacat yang membuat angkanya menyimpang

Pemeriksaan atas `LaporanKantinUtil` — mesin di balik seluruh laporan web —
menemukan laporan **"Detail Transaksi Penjualan"** dan **"Rincian Penjualan per
Barang"** sebenarnya sudah ada dan sudah memuat rincian produk per nota. Namun
ketiganya membawa cacat berikut.

### 1a. Baris yang dibatalkan ikut terhitung

Laporan POS di aplikasi kasir (`PosApi.daftarOrderDenganSesi`) menyaring
`COALESCE(a.aktif,true)=true`. Laporan web **tidak menyaring apa pun** — nol
kemunculan `p.aktif` di seluruh berkas. Akibatnya qty dan omzet untuk periode
yang sama bisa berbeda antara dua laporan tanpa penjelasan; selisih semacam itu
merusak kepercayaan pada seluruh laporan, bukan hanya satu.

Ditegakkan di **satu titik**, `klausaPeriodeItemPenjualan()`, yang menggantikan
pemanggilan `klausaTanggal("p.waktu", …)` pada **19 kueri** berbasis
`koperasi.pembelian`.

### 1b. Kolom "Kasir" memakai metadata audit

Tiga laporan — Penerimaan Per Kasir, Penjualan per Kasir per Hari, dan Detail
Transaksi Penjualan — memakai `h.oleh` sebagai nama kasir. Kolom itu metadata
audit: berisi siapa yang terakhir menulis baris, dan pada jalur sinkronisasi
dapat berisi penanda sistem seperti `external_update`. Laporan bisa
mengelompokkan penjualan ke "kasir" yang tidak pernah melayani transaksinya.

Kini memakai `kasir_login_nama` — snapshot kasir pada nota, sumber yang sama
dengan laporan di aplikasi kasir.

### 1c. Penjualan produk yang sudah dihapus hilang tanpa jejak

Laporan rincian memakai `join koperasi.produk` (INNER). Bila produknya sudah
dihapus dari master, baris penjualannya **hilang dari laporan** dan total
laporan lebih kecil daripada penjualan sebenarnya — tanpa peringatan apa pun.
Kini `left join` dengan label jatuh ke nama dan kode snapshot yang tersimpan di
baris penjualan; pencarian produk pada dua laporan rincian ikut membaca
snapshot itu supaya produk terhapus tetap dapat dicari.

**Rincian Penjualan per Barang** juga mendapat kolom **Kasir**.

Bukti: `TesLaporanWeb` memanggil `LaporanKantinUtil.build()` apa adanya lewat
`HttpServletRequest` tiruan (Proxy dinamis, sesi berisi pengguna nyata) —
**10/10 lulus**, termasuk "baris dibatalkan tidak lagi muncul", "penjualan
produk yang sudah dihapus tetap muncul", dan "kolom Kasir memakai
kasir_login_nama, bukan metadata audit".

## 2. Filter produk dan kasir pada tab Rincian Produk

Server sudah mendukung filter `produk` dan `kasir` (dipakai Report Order), tetapi
tab baru belum mengeksposnya. Kini tersedia dua kolom pencarian, ikut terbawa ke
Preview/PDF/Excel/Word dan tertulis pada subjudul laporan sehingga hasil cetak
menyatakan filter apa yang sedang berlaku.

## 3. Saklar UOM di layar Konfigurasi

`kantin_uom_balikkan_pcs_massal` dan penanda `kantin_uom_isi_pcs_massal_selesai`
sebelumnya hanya bisa diubah lewat SQL — bertentangan dengan tujuan dok. 63
menghapus SQL manual. Keduanya kini terdaftar di layar Konfigurasi pada kelompok
**Satuan / UOM**, lengkap dengan keterangan bahayanya.

## 4. Rekap per produk

Tab Rincian Produk mendapat mode **Rekap per produk**: satu baris per produk
dengan Qty, jumlah transaksi, dan Total.

Rekap sengaja dihitung dari **baris rincian yang sama**, bukan dari kueri agregat
tersendiri. Dua sumber angka untuk hal yang sama pasti berselisih begitu salah
satu filternya berubah, dan pemilik tidak punya cara tahu mana yang benar.
Jumlah transaksi dihitung dari identitas nota yang unik — satu nota yang memuat
produk sama pada dua baris tetap dihitung satu transaksi.

## 5. Ekspor lintas halaman

Skenario paginasi ditambahkan ke harness: 13 transaksi dengan `pageSize` 10.
Gabungan seluruh halaman menghasilkan **27 baris item** dan `total` **13
transaksi** — membuktikan halaman kedua benar-benar terunduh, bukan berhenti di
halaman pertama seperti yang akan terjadi bila memakai helper ekspor bersama
(lihat dok. 64).

## Bukti keseluruhan

| Uji | Hasil |
| --- | --- |
| `TesLaporanWeb` (laporan web) | 10/10 |
| `TesRincianProduk` (endpoint + paginasi) | 18/18 |
| `rekap_produk_test.dart` | 7/7 |
| `rincian_produk_halaman_test.dart` | 6/6 |
| `flutter analyze` | bersih |

## Yang perlu dilakukan agar sampai ke pengguna

Perbaikan laporan web (butir 1) dan saklar Konfigurasi (butir 3) berlaku setelah
**build server dipasang ke ebisnis.id dan Tomcat di-restart** — tanpa rilis
aplikasi. Butir 2 dan 4 ada di aplikasi kasir sehingga menuntut rilis baru.
