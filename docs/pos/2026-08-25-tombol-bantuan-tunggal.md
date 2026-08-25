# Tombol Bantuan Tunggal

Tanggal: 2026-08-25

## Masalah

Halaman yang menggunakan `AppShell` menampilkan dua akses bantuan sekaligus:

- tombol `Bantuan` pada header desktop atau ikon bantuan pada AppBar mobile; dan
- tombol bantuan mengambang berbentuk `?`.

Duplikasi terlihat antara lain pada halaman Permintaan Pembelian (PR).

## Perubahan

- Menghapus tombol `Bantuan` langsung dari header desktop.
- Menghapus ikon `Bantuan` langsung dari AppBar mobile.
- Mempertahankan satu tombol bantuan mengambang `?` pada desktop dan mobile.
- Mempertahankan tombol `Tanya Jawab` karena fungsinya berbeda dari bantuan umum.
- Menambahkan key pengujian `tombol-bantuan-mengambang` agar jumlah akses bantuan
  dapat diverifikasi secara otomatis.

Perubahan dilakukan pada `AppShell`, sehingga berlaku konsisten untuk seluruh halaman
yang menggunakan shell tersebut, bukan hanya halaman PR.

## Uji regresi

Pengujian widget memastikan:

- desktop hanya memiliki satu tombol bantuan mengambang;
- mobile hanya memiliki satu tombol bantuan mengambang;
- menu bantuan tetap dapat membuka bantuan kontekstual halaman; dan
- tombol Tanya Jawab tetap membuka daftar tanya jawab halaman.
