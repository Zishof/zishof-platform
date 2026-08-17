# Al-Bahjah POS 1.33.57

## Pemulihan dan rekonsiliasi transaksi

- Menambahkan tombol supervisor **Bandingkan Lokal ↔ Server** pada Riwayat Penjualan.
- Menampilkan ringkasan transaksi yang sama, hanya lokal, hanya server, berbeda nominal, dan terduplikasi.
- Menampilkan tabel audit per kode transaksi sebelum supervisor menjalankan sinkronisasi.
- Menampilkan asal transaksi pada kedua sisi: username kasir serta nama/ID mesin POS lokal dan server.
- Perbandingan bersifat baca-saja; tombol sinkronisasi tetap menjadi aksi terpisah.
- Mempertahankan input transaksi pemulihan supervisor, sinkronisasi dua arah idempoten, serta cadangan lokal persisten.
- Checkout menyimpan transaksi ke SQLite terlebih dahulu dan tidak lagi menunggu respons server.
- Pengiriman pertama berjalan di background; kegagalan jaringan/server dicoba kembali setelah jeda minimal 10 menit.
- Perangkat kasir pada toko yang sama saling mencadangkan transaksi server, tanpa mengambil transaksi toko lain.

## Penyimpanan lokal

- Tetap menggunakan satu tabel transaksi berindeks dengan `kode_unik` sebagai kunci deduplikasi.
- Tidak membuat tabel harian dinamis karena memperumit migrasi, transaksi atomik, dan rekap lintas tanggal.

## Data demo terkontrol

- Menambahkan flag `toko_demo` pada pengelolaan toko di Desktop, Android, JSP, dan ZKoss.
- Tombol pembuatan 50.000 produk dan 200.000 transaksi hanya muncul bagi admin ketika toko demo dan konfigurasi `data_sample_ebisnis` sama-sama aktif.
- Proses pembuatan data berjalan di background dan idempoten agar aman dijalankan ulang.
