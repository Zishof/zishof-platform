# v1.33.37

- Memperluas Analisis Riwayat Penjualan dengan pola hari, distribusi nilai
  keranjang, rekap retur, biaya diskon/cashback, eksposur selisih transaksi,
  konsentrasi produk, dan rekomendasi tindakan yang dapat dijelaskan.
- Menambahkan seluruh rekap analitik baru ke dokumen PDF dan membatasi data
  kasir biasa hanya pada transaksi miliknya melalui validasi server.
- Memastikan transaksi kasir terhubung ke sesi kas berdasarkan akun, toko, dan
  perangkat serta menyajikan laporan tutup kas lengkap per metode pembayaran.
- Memperjelas pesan kesalahan pembayaran untuk pengguna dengan detail teknis
  yang tetap dapat dibuka dan disalin.
- Menampilkan barang yang baru dipindai pada urutan teratas keranjang.
- Menjaga transaksi yang gagal karena jaringan di antrean lokal untuk dicoba
  ulang secara otomatis.
