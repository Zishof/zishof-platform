# Deduplikasi Filter Status Mahasiswa

Tanggal: 3 September 2026

## Gejala

Filter lanjutan pada menu Mahasiswa menampilkan pilihan **Nonaktif - N** dua
kali.

## Penyebab

Combo Status memuat seluruh baris `StatusMahasiswa` dari database. Pada data
lama terdapat lebih dari satu baris status dengan kode EPSBED `N`. Walaupun
labelnya sama, ID entity berbeda sehingga helper combo menampilkan keduanya.

Menghapus salah satu pilihan hanya berdasarkan ID tidak aman: riwayat mahasiswa
lama mungkin masih merujuk ID duplikat yang berbeda. Jika filter tetap
membandingkan ID, sebagian mahasiswa berstatus Nonaktif dapat tidak ikut hasil.

## Perbaikan

- Opsi Status pada filter Mahasiswa dideduplikasi menggunakan kode EPSBED yang
  dinormalisasi; nama dinormalisasi menjadi fallback bila kode kosong.
- Item **Semua** tetap dipertahankan.
- Pemilihan dari parameter URL dipetakan secara semantik ke opsi yang masih
  tampil.
- Penyaringan kandidat dan renderer membandingkan status memakai kode semantik,
  dengan ID sebagai fallback. Karena itu satu opsi **Nonaktif - N** tetap
  mencakup seluruh ID lama berkode `N`.
- Tidak ada penghapusan atau mutasi data master pada perbaikan ini.

## Verifikasi

- Kedua source mirror memiliki hash SHA-256 identik.
- Helper deduplikasi dan pembanding semantik terdeteksi pada bytecode hasil
  kompilasi.
- `mvn -DskipTests compile`: **BUILD SUCCESS**.

## UAT

1. Buka menu Mahasiswa lalu buka Filter Pencarian Lanjut.
2. Buka pilihan Status dan pastikan **Nonaktif - N** hanya muncul satu kali.
3. Pilih **Nonaktif - N**, terapkan filter, dan pastikan seluruh mahasiswa
   Nonaktif tetap tampil, termasuk data lama.
4. Pilih status lain dan **Semua** untuk memastikan perilaku filter tetap sama.
