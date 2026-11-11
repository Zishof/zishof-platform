# POS Desktop dan Android: tabel 15 baris per halaman

## Cakupan yang diverifikasi

- Semua layar POS yang memakai `AppDataTable` menampilkan paling banyak 15 baris per halaman. Komponen ini dipakai pada layar utama dan daftar dalam dialog.
- Tabel Material langsung memakai `AppPagedDataTable`; popup rincian angka/kartu memakai kontrol halaman 15 baris; pratinjau Perancang Laporan sekarang memakai tabel berhalaman dan tidak lagi membatasi data pratinjau ke 100 baris.
- Daftar Price Tag diseragamkan dari 50 menjadi 15 item per permintaan dan per halaman.
- Ukuran halaman pada daftar yang sebelumnya memakai 10 atau 25 diseragamkan menjadi 15.
- Manajemen Rak Produk meminta halaman 15 baris dari layanan, bukan mengambil 500 baris sekaligus. Jumlah dan ringkasan stok/nilai untuk hasil yang difilter tetap dihitung terpisah.
- Popup rincian tetap menggunakan semua baris yang sesuai untuk pencarian, Excel, dan PDF; hanya jumlah baris yang digambar pada satu halaman popup dibatasi menjadi 15.

## Cara kerja dan perlindungan

1. Komponen tabel bersama memotong daftar layar menjadi halaman 15 baris; tombol halaman sebelumnya/berikutnya dinonaktifkan di batas daftar.
2. Jika daftar mengecil saat pengguna berada di halaman akhir, tampilan kembali ke halaman terakhir yang masih ada dan tidak menjadi kosong.
3. Pada daftar Rak Produk, perubahan rak atau kata pencarian kembali ke halaman pertama dan menghapus pilihan yang terkait filter lama. Pilihan produk di halaman lain tetap dipertahankan selama rak dan pencarian tidak berubah.
4. Ekspor/cetak pada popup rincian menggunakan seluruh hasil saringan, bukan hanya halaman yang sedang terlihat.
5. Tabel langsung yang baru ditambahkan harus memakai `AppDataTable` atau `AppPagedDataTable`; popup rincian harus memiliki paging 15 baris. Uji kontrak mempertahankan batas jumlah baris dan navigasi halaman.

## Cakupan perangkat

POS Desktop Windows dan Android memakai source Flutter yang sama. Perilaku tampilan 15 baris dan navigasi halaman berlaku pada keduanya.

## Batasan pengambilan data

Paging tampilan mengurangi jumlah baris yang dirender sekaligus. Namun, pada layar yang masih meminta seluruh daftar dari server atau penyimpanan lokal sebelum membaginya di layar, ukuran respons awal belum otomatis berubah menjadi 15. Pengambilan bertahap dari server telah tersedia untuk daftar yang memang mendukung parameter halaman, termasuk Manajemen Rak Produk, dan tetap perlu diperluas per layanan untuk layar lain yang memuat data besar. Karena itu, jangan menyimpulkan waktu pemuatan semua menu sudah berkurang hanya dari jumlah baris yang terlihat.
