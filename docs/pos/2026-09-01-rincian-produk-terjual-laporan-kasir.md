# 64. Rincian Produk Terjual pada Laporan Kasir

Tanggal: 1 September 2026  
Permintaan: An Nahl (via Fikri Rizky Pratama, 1 September 2026 pukul 19.59) —
"hasil download-nya ada rincian **produk apa saja yang terjual**, bukan hanya
per transaksi"  
Rujukan: dok. 59 (satuan jual), dok. 63 (master UOM)

## Masalah

Laporan Transaksi memiliki enam tab (Report Order, Report Sesi, Transaksi Per
Kasir, Report Payment, Penjualan per Kasir, Penerimaan per Kasir). Seluruhnya
berhenti di tingkat **transaksi**: satu baris memuat nota, waktu, kasir, metode,
dan jumlah. Tidak ada satu pun yang memperlihatkan barang apa yang dibeli, baik
di layar maupun pada unduhan PDF/Excel/Word.

Laporan analitik "Produk Terlaris" memang sudah ada di layar Ringkasan dan
Riwayat Penjualan, tetapi bentuknya peringkat agregat untuk analisis — bukan
rincian per nota yang dibutuhkan kasir dan pemeriksa.

## Yang ditambahkan

Tab baru **Rincian Produk** pada Laporan Transaksi: satu baris per produk pada
tiap transaksi, dengan tombol Preview/PDF/Excel/Word yang sama seperti tab lain.

Kolom unduhan: Waktu, Nota, Kasir, Kode, Produk, Qty, Harga, Diskon, Total.

## Keputusan rancangan

**Sumber transaksinya memakai ulang mesin kueri Report Order**
(`daftarOrderDenganSesi`), bukan kueri baru. Konsekuensinya penting: penomoran
nota "Order {toko} - {sesi} - {urut}", seluruh filter (tanggal, jam, kasir,
mesin, metode, nominal), dan pembatasan hak kasir otomatis **identik** dengan
Report Order. Bila dibuat kueri sendiri, dua laporan atas periode yang sama bisa
menampilkan himpunan transaksi berbeda begitu salah satu filternya berubah, dan
logika penomoran nota harus disalin — dua sumber kebenaran untuk hal yang sama.

**Paginasi tetap dihitung dalam TRANSAKSI**, bukan item: satu halaman memuat
seluruh item milik transaksi pada halaman itu, sehingga sebuah nota tidak pernah
terpotong di tengah.

**Kuantitas ditampilkan memakai satuan yang dipilih kasir** (dok. 59):
"1 Lusin (12 Pcs)" bila dijual per satuan besar, "3 Pcs" bila per satuan dasar.
Angka bulat ditulis tanpa ekor desimal.

**Pembatasan hak kasir ikut berlaku pada rincian.** Akun non-supervisor hanya
melihat transaksinya sendiri — sama seperti Report Order. Ini diuji secara
eksplisit, karena laporan rincian yang lolos batas kasir akan membocorkan
belanja pelanggan kasir lain.

## Jebakan yang ditutup: ekspor terpotong diam-diam

Helper ekspor bersama (`_ambilSemuaBarisLaporan`) berhenti mengambil halaman
ketika **jumlah baris terkumpul mencapai `total`**. Aturan itu benar untuk
laporan lain, di mana satu baris = satu transaksi. Pada laporan rincian, `total`
berarti jumlah transaksi sedangkan barisnya adalah item — karena satu transaksi
lazimnya berisi beberapa item, syarat itu **terpenuhi sejak halaman pertama**
dan sisa halaman tidak pernah terunduh. PDF/Excel akan tampak berhasil padahal
isinya terpotong; kesalahan seperti ini tidak terlihat kecuali seseorang
menghitung ulang totalnya.

Karena itu laporan ini memakai pengambil halaman sendiri yang berhenti
berdasarkan **nomor halaman**, dihitung `totalHalamanRincian(totalTransaksi,
ukuranHalaman)`. Fungsi itu sengaja dipisah agar dapat diuji tanpa jaringan.

## Bukti

Server — `TesRincianProduk` memanggil `PosApi.prosesLaporanRincianProduk` lewat
refleksi, persis jalur API, atas fixture transaksi tiga item: **15/15 lulus**,
termasuk:

- 3 baris rincian item (bukan 1 baris transaksi);
- nomor nota "Order 001 - 0000 - 001" terisi dan **sama** untuk seluruh item
  dalam satu nota (konsisten dengan Report Order);
- label qty "1 Lusin (12 PCS)" untuk penjualan per satuan besar dan "3 PCS"
  untuk satuan dasar;
- harga satuan, diskon, dan total per item terbawa; total nilai item 34.500;
- filter kasir dan filter tanggal juga membatasi rincian.

Klien — `flutter analyze` bersih; `rincian_produk_halaman_test.dart` **6/6**
lulus, termasuk kasus "250 transaksi = tiga halaman (halaman terakhir tidak
hilang)" dan pembagian nol pada ukuran halaman tidak sah.

## Yang belum dikerjakan

Rekap per produk (satu baris per produk dengan total qty dan nilai se-periode)
**tidak** ditambahkan di sini: bentuk itu sudah tersedia sebagai "Produk
Terlaris" dan "Rekap Produk Terlaris" di layar Ringkasan serta Riwayat
Penjualan. Menambahkannya lagi di sini akan membuat dua angka rekap yang
sumbernya berbeda. Bila pemilik menghendaki rekap yang mengikuti filter Laporan
Transaksi persis, itu keputusan tersendiri dan sebaiknya dibangun dari mesin
kueri yang sama seperti tab ini.

Agar tersedia bagi pengguna, build server perlu dipasang ke ebisnis.id dan
aplikasi kasir dirilis ulang.
