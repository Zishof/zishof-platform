# POS v1.34.28 — Sinkronisasi Saldo Voucher dan Ganti Password

Tanggal rilis: 9 September 2026

## Perbaikan saldo voucher

- Saldo pada `Pelanggan > Saldo Voucher` sekarang memakai formula resmi yang sama dengan saldo pada kasir/POS.
- Voucher dan cashback kedaluwarsa ikut diperhitungkan.
- Pembelian dengan pembayaran gabungan hingga lima metode ikut mengurangi saldo sesuai konfigurasi cara pembayaran.
- Selisih non-transaksi, seperti voucher kedaluwarsa, direkonsiliasi sebagai koreksi keluar/masuk sehingga rumus `Saldo Awal + Masuk - Keluar = Saldo Akhir` tetap konsisten.
- Server lama tetap didukung sebagai fallback selama pembaruan backend belum diterapkan.

Kasus verifikasi produksi untuk member `20190901041`:

- Top-up lama: Rp45.000
- Pemakaian lama: Rp21.500
- Sisa Rp23.500 kedaluwarsa setelah 25 Agustus 2026
- Top-up baru 8 September 2026: Rp200.000
- Saldo resmi: Rp200.000

Dengan filter 1–8 September 2026, hasil yang benar adalah saldo awal Rp0, masuk Rp200.000, keluar Rp0, dan saldo akhir Rp200.000.

## Perbaikan ganti password

- Form Akun Saya mengirim kata sandi lama, kata sandi baru, dan konfirmasi kata sandi ke server.
- Pesan kegagalan server ditampilkan lengkap agar pengguna mengetahui kolom atau syarat yang perlu diperbaiki.

## Validasi

- Regresi formula backend untuk voucher aktif, kedaluwarsa, cashback, dan saldo minimum nol.
- Uji Flutter untuk penggunaan snapshot saldo resmi dan kompatibilitas server lama.
- Uji kontrak permintaan ganti password dan penanganan detail galat.

Pembaruan backend dan aplikasi wajib dipasang bersama agar laporan saldo memakai snapshot resmi server.
