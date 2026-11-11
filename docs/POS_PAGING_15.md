# POS Desktop dan Android: tabel 15 baris per halaman

## Perubahan

- `AppDataTable` menjadi komponen standar untuk daftar berbentuk tabel dan menampilkan maksimal 15 baris pada satu halaman.
- Tabel Flutter `DataTable` langsung menggunakan `AppPagedDataTable`; tabel ringkasan yang memiliki maksimal 15 baris tetap tampil utuh.
- Ukuran daftar berhalaman pada layar yang sebelumnya menggunakan 10 atau 25 baris disamakan menjadi 15.
- Layar Manajemen Rak Produk meminta halaman 15 baris dari layanan, bukan mengambil 500 baris sekaligus. Layanan menghitung jumlah dan ringkasan stok/nilai dengan filter yang sama, mengirim hanya satu halaman, dan menjaga permintaan lama tanpa parameter halaman agar tetap bekerja untuk keperluan ekspor.
- Pembacaan Rak Produk dengan paging tidak menjalankan sinkronisasi stok seluruh toko pada setiap pergantian halaman. Penyesuaian stok tetap dilakukan melalui aksi sinkronisasi yang sudah tersedia.

## Cara kerja dan perlindungan

1. Perubahan halaman mengirim nomor halaman, ukuran 15, identitas toko/rak, dan kata pencarian yang sama.
2. Layanan membatasi hasil di sisi basis data dan mengembalikan jumlah total serta ringkasan lengkap untuk filter tersebut.
3. Jika data berkurang saat pengguna berada di halaman yang terlalu tinggi, layanan mengarahkan kembali ke halaman terakhir yang masih tersedia.
4. Pergantian halaman tidak membuang pilihan produk yang telah dibuat di halaman lain. Mengganti rak atau kata pencarian mengosongkan pilihan agar tindakan massal tidak mengenai hasil lama yang tersembunyi.
5. Daftar yang dipakai untuk ekspor atau impor tetap mengikuti alur ekspor/impor penuh yang telah ada; tabel di layar tidak lagi mengirim semua baris ke perangkat hanya untuk ditampilkan.

## Cakupan perangkat

Desktop Windows dan Android menggunakan layar Flutter yang sama sehingga aturan tampilan 15 baris berlaku pada keduanya. Komponen server-paged yang sudah ada tetap memakai kendali halaman milik layarnya agar tidak terjadi pemotongan dua kali.

## Batasan

Komponen lokal membatasi jumlah baris yang digambar, tetapi tidak dapat mengurangi jumlah data yang sebelumnya sudah dimuat penuh oleh layar. Untuk daftar besar yang belum memiliki permintaan halaman dari server atau penyimpanan lokal, pengambilan bertahap perlu ditambahkan pada layanan layar terkait. Halaman Rak Produk pada gambar sudah memakai pengambilan sisi server per 15 data.
