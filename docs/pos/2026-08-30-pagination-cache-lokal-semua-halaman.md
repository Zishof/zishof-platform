# Pagination cache lokal untuk seluruh halaman daftar

## Masalah

Snapshot master yang sudah tersinkron dapat berisi puluhan ribu baris. Layar
daftar sebelumnya membaca dan mengurai seluruh JSON cache, walaupun paginator
hanya menampilkan sebagian kecil baris. Pekerjaan tersebut berlangsung pada
alur UI sehingga layar dapat terlihat mandek.

## Aturan wajib

1. Layar daftar yang memakai `MasterOffline.daftarCacheDulu` wajib mengirim
   kontrak paginasi (`page` + `page_size`, atau `limit` + `offset`).
2. Cache referensi berbentuk daftar diindeks per baris dalam tabel SQLite
   `cache_referensi_baris`. Pembacaan lokal menggunakan `LIMIT/OFFSET`, dan
   `total` tetap berisi jumlah seluruh baris untuk kebutuhan paginator.
3. Snapshot instalasi lama diindeks otomatis saat pertama kali dibaca. Simpan
   berikutnya memperbarui snapshot dan indeks baris dalam satu transaksi.
4. Request yang tidak mengirim parameter paginasi tetap memperoleh dataset
   lengkap. Pengecualian ini hanya untuk kalkulasi/agregasi yang memang perlu
   seluruh data; jangan digunakan oleh layar daftar biasa.
5. Penyegaran server berjalan setelah halaman lokal ditampilkan. Kegagalan
   jaringan tidak boleh mengosongkan halaman lokal atau memblokir navigasi.
6. Baris bertanda hapus lokal (`_dihapus`) tidak dihitung dan tidak ditampilkan
   dalam halaman cache.

## Cakupan

Per 30 Agustus 2026 terdapat 93 pemanggilan `daftarCacheDulu` pada 81 berkas
layar/layanan. Perubahan dilakukan di satu pintu layanan sehingga seluruh
pemanggil yang sudah mengirim kontrak paginasi otomatis memakai pembacaan
SQLite per halaman. Master Produk tetap memakai tabel terstruktur
`produk_cache` karena membutuhkan filter produk yang lebih lengkap.

## UAT minimum

- Isi cache sedikitnya 40 baris, buka halaman kedua dengan ukuran 15, dan
  pastikan yang tampil baris 16–30 serta total tetap 40.
- Putuskan jaringan, pindah halaman, dan pastikan cache lokal tetap tampil.
- Pastikan request tanpa paginasi tetap menerima seluruh dataset untuk proses
  agregasi yang sah.
- Pastikan data pending/gagal kirim lokal tidak tertimpa hasil server.
