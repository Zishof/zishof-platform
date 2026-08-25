# Perbaikan Scrollbar Daftar Desktop — 25 Agustus 2026

## Masalah

Halaman **Kode Akun (COA)** menampilkan daftar panjang di area konten yang
tingginya terbatas, tetapi tidak menyediakan scrollbar vertikal desktop yang
terlihat. Baris di bagian bawah menjadi sulit dijangkau dan pengguna tidak
mendapat petunjuk bahwa masih ada data lanjutan.

## Akar masalah

`AppDataTable`, komponen tabel bersama yang dipakai halaman Kode Akun dan
puluhan halaman daftar lain, belum memiliki `ScrollController` dan
`Scrollbar` vertikal eksplisit. Ketika tabel ditempatkan di dalam `Expanded`
atau `TabBarView`, tinggi konten melebihi viewport dan terpotong tanpa bilah
scroll yang dapat diseret dengan mouse.

## Perubahan

- Menambahkan controller scroll vertikal pada `AppDataTable`.
- Pada viewport dengan tinggi terbatas, tabel dibungkus scrollbar desktop yang
  selalu terlihat, memiliki track, interaktif, dan dapat diseret.
- Pada induk dengan tinggi tidak terbatas, perilaku lama dipertahankan untuk
  menghindari konflik nested-scroll dengan halaman yang sudah memiliki scroll
  utama.
- Posisi scroll dikembalikan ke atas ketika pengguna berpindah halaman data.
- Controller selalu dibersihkan melalui `dispose()`.
- Perbaikan berlaku otomatis pada seluruh 72 screen yang menggunakan
  `AppDataTable`, bukan hanya menu Kode Akun.

## Verifikasi

- `dart format` lulus.
- Widget test `tabel_paging_otomatis_test.dart` lulus 7/7, termasuk pengujian
  scrollbar desktop pada area tabel terbatas.
- `flutter analyze` pada komponen bersama dan halaman Kode Akun tidak
  menemukan error atau warning. Tersisa satu info lint yang sudah ada
  sebelumnya pada `kode_akun_screen.dart:673` dan tidak berkaitan dengan
  perubahan scrollbar.

