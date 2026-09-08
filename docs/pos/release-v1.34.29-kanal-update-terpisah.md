# POS v1.34.29 — Kanal Update Al-Bahjah dan Nahl Terpisah

Tanggal rilis: 9 September 2026

## Perbaikan

- Al-Bahjah hanya membaca tag rilis `albahjah-*`.
- Nahl hanya membaca tag rilis `nahl-*`.
- Paket Nahl yang namanya mengandung teks `Al-Bahjah An-Nahl` ditolak oleh pemilih aset Al-Bahjah.
- Rilis dengan versi lebih tinggi pada satu kanal tidak memunculkan notifikasi atau unduhan pada kanal lain.

## Isi build

Build 1.34.29+192 tetap mencakup seluruh perbaikan 1.34.28:

- sinkronisasi saldo voucher dengan saldo resmi kasir;
- perhitungan voucher/cashback kedaluwarsa dan pembayaran gabungan;
- perbaikan Akun Saya > Ganti Password;
- rekap produk terjual digabung per produk;
- rincian penerimaan tunai pada Excel;
- Total HPP per item Bulk Entry Kulakan.

## Aturan publikasi

Al-Bahjah dan Nahl harus dipublikasikan sebagai dua GitHub Release terpisah. Jangan menggabungkan keduanya dalam satu tag rilis.
