# Riwayat perubahan produk

Tanggal implementasi: 29 Agustus 2026

## Tujuan

Halaman **Master Data > Produk** memiliki tab **Riwayat Perubahan**. Data pada
tab berasal langsung dari tabel audit Hibernate Envers di server, bukan dari
cache SQLite perangkat. Dengan demikian jejak audit tetap mempunyai satu sumber
kebenaran dan tidak dapat diubah dari POS.

## Informasi yang ditampilkan

- produk, kode, barcode, waktu, nomor revisi, tipe perubahan, dan pelaku;
- nama field bisnis yang berubah dengan label ramah pengguna;
- jenis data, misalnya Angka, Teks, Status Ya/Tidak, Tanggal/Waktu, atau
  Referensi Master;
- nilai sebelum dan sesudah dalam pola **dari → menjadi**;
- nilai kosong dijelaskan sebagai `(kosong)`, bukan disamarkan menjadi angka
  nol atau teks lain;
- perubahan teknis `oleh`, `olehId`, `tanggal_dirubah`, dan `kunciUnik` tidak
  dicampur ke daftar perubahan bisnis.

Contoh: `Harga jual: Rp 10.000 → Rp 12.000`, `Status aktif: Aktif → Nonaktif`,
atau `Satuan pembelian: Pcs → Dus`.

## Kontrak API

`revisi_daftar` tetap memakai parameter `entitas=produk` dan `id`. Setiap revisi
sekarang menyertakan array `perubahan` dengan field `field`, `jenisData`,
`dari`, dan `menjadi`. Perbandingan dilakukan server-side terhadap snapshot
Envers sebelumnya. Aksi `revisi_jelajah` dipakai untuk daftar lintas produk
sesuai rentang tanggal, jenis perubahan, toko, dan kata kunci.

Riwayat bersifat online-only. Saat server tidak dapat dihubungi, pengguna diberi
pesan bahwa audit belum dapat dimuat dan dapat mencoba kembali; aplikasi tidak
mengarang riwayat dari cache produk terakhir.

## UAT

1. Ubah satu produk, misalnya harga jual dan satuan pembelian, lalu simpan.
2. Buka tab **Riwayat Perubahan**, tentukan rentang tanggal, lalu tekan
   **Tampilkan**.
3. Pastikan produk, waktu, pelaku, dan tipe `UBAH` terlihat.
4. Klik baris dan pastikan kedua field menampilkan nilai lama → nilai baru.
5. Tambah dan nonaktifkan produk untuk memverifikasi tipe `TAMBAH` dan `UBAH`.
6. Putuskan jaringan; tab harus menjelaskan bahwa audit server belum dapat
   dibaca tanpa menghapus data produk lokal.

