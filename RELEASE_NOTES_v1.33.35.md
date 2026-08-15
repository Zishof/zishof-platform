# v1.33.35

- Menambahkan retry otomatis setiap 10 menit untuk transaksi POS yang sudah
  tersimpan di antrean lokal tetapi belum terkirim karena jaringan/timeout.
- Memisahkan kepemilikan antrean berdasarkan akun, toko, dan perangkat agar
  transaksi offline tidak terkirim memakai akun kasir lain setelah pergantian
  login.
- Mencegah polling pesanan online tumpang tindih dan menggunakan backoff 10
  menit saat server tidak dapat dijangkau.
- Memisahkan cursor notifikasi pesanan per akun dan toko sehingga perpindahan
  toko tidak melewatkan pesanan.
- Menambahkan identitas perangkat pada payload pembayaran sebagai dasar audit
  dan pengikatan sesi kasir per perangkat.
