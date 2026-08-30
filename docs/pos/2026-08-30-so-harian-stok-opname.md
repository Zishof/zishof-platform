# SO Harian pada Stok Opname

Tanggal: 30 Agustus 2026

## Tujuan

Menyiapkan lembar pemeriksaan harian yang hanya berisi produk yang benar-benar
terjual pada tanggal pilihan. Petugas dapat mencocokkan jumlah keluar dengan
sisa fisik tanpa harus mengunduh seluruh katalog produk.

## Perilaku aplikasi

Menu **Stok Opname** sekarang mempunyai tab **SO Harian** dengan fungsi:

- memilih tanggal (nilai awal adalah hari ini);
- menampilkan kode/barcode, produk, satuan, penjualan bruto, retur yang kembali
  ke stok, penjualan bersih, dan stok sistem saat daftar dibaca;
- menyimpan checklist selesai per toko dan tanggal pada perangkat kasir;
- mengunduh form Excel yang menyediakan kolom stok fisik, selisih, petugas,
  dan keterangan;
- mengunggah kembali form Excel melalui pratinjau validasi sebelum stok
  berubah;
- mencetak form PDF untuk penghitungan manual;
- memakai snapshot lokal terakhir ketika koneksi terputus, disertai penanda
  bahwa data yang tampil merupakan data tersimpan.

Checklist bukan transaksi stok dan tidak mengubah saldo. Hasil hitung dapat
dimasukkan melalui **Input Opname**, **SO by Scan**, atau dengan mengisi kolom
`STOK_FISIK` pada form SO Harian lalu menekan **Unggah Excel**. Unggahan Excel
menampilkan pratinjau perubahan dari stok sistem menjadi stok fisik. Seluruh
baris baru disimpan sebagai satu batch setelah dikonfirmasi; jika satu baris
tidak valid, tidak ada stok yang berubah. Entri yang salah hanya boleh
dibatalkan oleh supervisor melalui alur pembatalan SO yang sudah tersedia.

Sebelum pemeriksaan dimulai, petugas perlu menekan **Sinkronkan** dan memastikan
seluruh transaksi pending sudah berhasil dikirim. Transaksi yang masih pending
di perangkat belum tersedia dalam laporan server. Kolom **Sisa Stok Saat Ini**
adalah snapshot saat daftar dimuat, bukan saldo historis penutupan tanggal yang
dipilih. Penamaan dan petunjuk ini sengaja dibuat eksplisit agar pemeriksaan
tanggal lampau tidak keliru dibaca sebagai stok akhir pada tanggal tersebut.
Kolom **Terjual** adalah penjualan bruto pada tanggal pilihan, **Retur** adalah
barang yang kembali ke stok pada tanggal tersebut, dan **Bersih** adalah
Terjual dikurangi Retur.

## Kontrak server

Action SO Harian pada `PosApi`:

- `so_harian`, parameter `tanggal` berformat `YYYY-MM-DD`;
- `so_harian_download_excel`, parameter yang sama dan hasil berupa berkas XLSX
  Base64;
- `so_harian_upload_excel_preview`, parameter `tanggal` dan `file_base64`,
  hanya memvalidasi format, cakupan produk, nilai stok fisik, dan duplikasi;
- `so_harian_upload_excel`, parameter yang sama, memvalidasi ulang kemudian
  menyimpan seluruh hasil hitung dalam satu transaksi database;
- `so_harian_ekspor_excel` tetap tersedia sebagai alias kompatibilitas untuk
  build POS lama.

Server menentukan toko dari sesi/payload yang sudah divalidasi. Query mengambil
penjualan dan retur dalam satu rentang hari `[00:00, 00:00 hari berikutnya)`,
lalu membaca stok produk pada snapshot yang sama. Implementasi tidak memakai
cast PostgreSQL `::TYPE`.

### Aturan wajib tipe hasil native SQL

Semua kolom hasil `createSQLQuery` pada alur Stok Opname dan SO Harian wajib
memiliki alias unik dan tipe Hibernate eksplisit melalui `addScalar`. Jangan
mengandalkan auto-discovery tipe Hibernate lama, khususnya untuk hasil campuran
angka dan teks. Contoh kontrak daftar SO Harian:

- `produk_id`: `Hibernate.LONG`;
- kode, barcode, nama produk, dan satuan: `Hibernate.STRING`;
- kuantitas terjual, retur, dan stok: `Hibernate.DOUBLE`.

Aturan yang sama diterapkan pada ringkasan, riwayat, perubahan stok, pemeriksaan
duplikasi unggahan, dan ekspor Excel. Alias SQL harus sama persis dengan nama
yang diberikan kepada `addScalar`. Query DML yang tidak mengembalikan result
set serta query entitas/HQL tidak memerlukan `addScalar`.

Aturan ini mencegah regresi PostgreSQL/Hibernate `SQLState 22003`, misalnya saat
nilai satuan teks `Pcs` keliru dibaca sebagai `DOUBLE` (`Bad value for type
double`). Setiap native query baru dengan hasil skalar wajib mengikuti pola ini
dan diverifikasi melalui kompilasi backend sebelum commit.

### Inisialisasi locale klien

Bootstrap seluruh varian Flutter wajib memanggil
`initializeDateFormatting('id_ID', null)` sebelum `runApp`. Tanpa inisialisasi
ini, format tanggal Indonesia pada tab SO Harian melempar
`LocaleDataException`; pada build release, panel dapat terlihat abu-abu/kosong
meskipun API server sudah sehat. Karena itu perbaikan insiden panel kosong
memerlukan backend dan build klien yang sama-sama terbaru.

Import hanya menerima template hasil unduhan SO Harian dan hanya menerima
produk yang memang terjual pada toko/tanggal tersebut. Baris tanpa stok fisik
dilewati. ID produk duplikat, stok fisik negatif/tidak valid, produk di luar
daftar, atau header yang berubah akan menolak penyimpanan. SHA-256 berkas
dicatat pada jurnal stok; file identik yang sudah pernah berhasil disimpan
ditolak agar koreksi tidak terjadi dua kali. Pengguna yang mengunggah tetap
menjadi pelaku audit; nama petugas di lembar kerja hanya menjadi keterangan.

## Urutan deployment

1. Deploy backend AIS SVN **r78609** yang memuat action dan pemetaan tipe
   hasil native SQL di atas.
2. UAT `so_harian` dengan akun dan toko aktif; respons harus `status=00`.
3. UAT unduh Excel dan pastikan formula selisih tersedia.
4. Isi beberapa nilai `STOK_FISIK`, jalankan pratinjau unggah, lalu pastikan
   penyimpanan menghasilkan jurnal SO dan stok baru yang sama di server.
5. Coba unggah file yang sama lagi; server harus menolak koreksi ganda.
6. Distribusikan build POS yang memuat tab baru.

Build aplikasi yang lebih baru tetap dapat membuka menu lain bila backend lama
belum dideploy, tetapi tab SO Harian akan menampilkan petunjuk kegagalan sampai
action server tersedia. Karena itu backend sebaiknya dipasang terlebih dahulu.

## Verifikasi pengembangan

- Analisis terarah API client, layar Stok Opname, dan test terkait:
  **No issues found**.
- Test kontrak SO Harian: **3 lulus**.
- Kompilasi terarah `KantinHelper` dan `StokOpnameScanUtil` pada kedua working
  copy backend: **lulus**.
- Perbaikan backend telah di-commit pada SVN **r78609**. Working copy deployment
  mempertahankan perubahan barcode dari sesi lain yang belum di-commit; bagian
  SO Harian/Stok Opname sudah terselaraskan ke r78609 tanpa konflik.
