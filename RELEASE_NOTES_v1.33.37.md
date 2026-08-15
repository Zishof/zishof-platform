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
- Menjaga transaksi yang gagal karena jaringan atau gangguan teknis server di
  antrean lokal agar kasir dapat langsung melayani pelanggan berikutnya.
- Menambahkan tab **Transaksi Pending** pada menu Pesanan, lengkap dengan
  status Pending/Sukses/Gagal, rincian barang, kendala terakhir, retry manual,
  dan interval retry otomatis yang dapat diatur (bawaan 10 menit).
- Mempertahankan transaksi yang sudah sukses di jurnal lokal sebagai bahan
  audit; hanya statusnya yang berubah menjadi Sukses dan datanya tidak dihapus.
- Menambahkan kartu keputusan dashboard per kasir, jenis produk, produk
  terlaris, dan toko; seluruh kartu dapat diklik untuk melihat ringkasannya.
- Menambahkan pengendalian benturan promo pada Aturan Diskon dan Diskon Grup:
  prioritas, izin penggabungan, dasar perhitungan bertingkat, serta grup
  eksklusif. Bawaan aman memilih satu promo berprioritas tertinggi.
- Menyeragamkan urutan dan penumpukan diskon pada API POS, ZK Kasir, dan toko
  online anggota, termasuk penerapan promo grup pada jalur ZK.
- Memindahkan seluruh tombol tindakan setelah pembayaran ke atas pratinjau
  struk agar kasir dapat langsung memulai transaksi baru tanpa menggulir
  rincian struk yang panjang.
