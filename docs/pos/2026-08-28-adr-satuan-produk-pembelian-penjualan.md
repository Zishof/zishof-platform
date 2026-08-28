# ADR: UOM Dasar, UOM Pembelian, dan Product Packaging

Tanggal: 28 Agustus 2026  
Status: Diterima, implementasi operasional selesai

## Konteks

Master `koperasi.satuan_produk` sudah menjadi katalog UOM, tetapi form Produk
sebelumnya menerima teks bebas dan otomatis membuat master baru. Hal ini dapat
menghasilkan variasi nama (`Pcs`, `PCS`, `Pc`) serta tidak menyediakan aturan
konversi. Satu faktor global juga tidak benar: satu `Dus` dapat berisi 12 botol
untuk produk A dan 24 botol untuk produk B.

## Keputusan

1. Produk wajib memiliki **Satuan Stok/Dasar** yang dipilih melalui searchbox
   dari master Satuan/UOM dan disimpan sebagai ID relasi. Teks yang hanya diketik
   tanpa memilih hasil tidak boleh disimpan.
2. Model produk membedakan:
   - satuan stok/dasar sebagai satuan saldo persediaan;
   - satuan pembelian/PO sebagai satuan bawaan dokumen pembelian;
   - satuan penjualan default mengikuti satuan stok/dasar.
3. Setiap UOM berada dalam satu kategori/dimensi, misalnya UNIT, BERAT, atau
   VOLUME. Satu kategori mempunyai tepat satu Reference UOM. UOM lain bertipe
   Bigger atau Smaller dengan rasio positif terhadap Reference dan presisi
   pembulatan eksplisit. Konversi lintas kategori ditolak.
4. Kemasan per produk dipisahkan sebagai **Product Packaging**. Contoh `Pack 6`
   dan `Box 24` mempunyai barcode/preset qty sendiri, tetapi tidak mengubah UOM
   akuntansi. Ini mencegah istilah `Dus` dengan isi berbeda diperlakukan sebagai
   satu rasio global.
5. Kuantitas dokumen wajib menyimpan snapshot: UOM input, qty input, faktor
   konversi, dan qty dasar. Dengan demikian perubahan faktor di kemudian hari
   tidak mengubah histori.
6. Faktor menggunakan angka desimal presisi/rasio positif dan aturan pembulatan
   eksplisit. Konversi identitas 1:1 tidak perlu disimpan sebagai baris terpisah.

## Tahapan aman

Tahap pertama mengubah form Produk menjadi relasi ID ke master UOM, menamai
field sebagai Satuan Stok/Dasar, dan menambah Satuan Pembelian/PO yang wajib satu
kategori. Master UOM menyimpan kategori, tipe Reference/Bigger/Smaller, rasio,
dan presisi. Form menampilkan simulasi hasil konversi PO. Kontrak API tetap
menerima `satuan_nama` untuk klien lama/importir, tetapi aplikasi baru mengirim
ID UOM.

Migrasi tidak menebak kategori data lama. Setiap UOM lama mula-mula ditempatkan
di kategori `LEGACY_<id>` sebagai Reference 1:1. Admin kemudian menggabungkannya
secara eksplisit, misalnya Pcs sebagai Reference kategori UNIT dan Dus sebagai
Bigger dengan rasio 24. Pendekatan ini mencegah Kg, Liter, dan Pcs tanpa sengaja
dianggap dapat saling dikonversi.

Penerimaan/kulakan menyimpan snapshot `satuan_input`, `qty_input`,
`faktor_konversi`, dan `harga_beli_satuan_input`. Kolom `qty` dan harga satuan
existing tetap disimpan dalam Satuan Stok/Dasar agar rumus stok, FEFO, HPP,
retur, pembatalan faktur, dan laporan lama tidak berubah.

Product Packaging disimpan sebagai daftar tervalidasi dan ikut katalog serta
cache lokal secara atomik. Scan barcode utama menambah satu base unit; scan
barcode kemasan aktif menambah `qtyDasar` base unit. Packaging tetap bukan UOM
akuntansi dan tidak mengubah satuan transaksi.

## Edukasi pengguna

- UOM baru dibuat melalui **Master Data > Satuan/UOM**.
- Pada form Produk, user harus mencari lalu memilih hasil UOM, bukan hanya
  mengetik nama.
- Bila daftar kosong, tekan **Sinkronkan/Muat Ulang**. Jika tetap kosong, admin
  perlu memastikan UOM aktif dan hak akses menu tersedia.
- Produk yang dipakai sebagai resep harus mempunyai Jenis Item **Bahan Baku**.
  Bila pencarian menemukan nama yang sama tetapi jenisnya Produk (Dijual), ubah
  Jenis Item produk itu terlebih dahulu; jangan membuat produk duplikat.

## Konsekuensi

Relasi UOM menjadi konsisten dan dapat diaudit. Sebagai konsekuensi, produk tanpa
satuan tidak dapat disimpan melalui aplikasi baru sampai master UOM dipilih.
Purchase UOM yang berbeda dapat dikonfigurasi, dipratinjau, dan digunakan oleh
penerimaan. Kasir tetap membukukan UOM dasar, termasuk saat barcode Product
Packaging dipindai. Rollback darurat menggunakan
`sql/rollback_uom_kategori_pembelian_20260828.sql`; kolom snapshot tidak dihapus
agar histori audit tidak rusak.
