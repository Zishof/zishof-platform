# Perbaikan Header Penilaian RPS OBE

Tanggal: 3 September 2026

## Gejala

Pada tabel **Rincian Kurikulum** RPS OBE, kolom Penilaian terlihat berisi
`== Belum Ditentukan ==` atau seolah-olah kosong, padahal field
**Penilaian (Teknik & Kriteria)** pada modal sudah terisi.

## Analisis aliran data

Nilai field tidak hilang:

- Saat disimpan, nilai dimasukkan ke JSON melalui key `teknikDanKriteria`.
- Saat tabel dirender, nilai dibaca kembali dari key `teknikDanKriteria` yang
  sama.
- Nilai tersebut juga disalin ke `Pertemuan.tugasDanPenilaian` saat rincian
  pertemuan disegarkan.

Masalah sebenarnya berada pada struktur header tabel. Setiap row mempunyai
sepuluh cell dan cell pertama dipakai komponen ZK `Detail`. `Auxhead` sebelumnya
langsung dimulai dari **Minggu Ke**, tanpa header kosong untuk cell `Detail`.
Semua judul kemudian bergeser satu kolom ke kiri. Nilai CPMK
`== Belum Ditentukan ==` tampak berada di bawah judul Penilaian, sedangkan nilai
Penilaian sebenarnya berada lebih ke kanan.

## Perbaikan

- Menambahkan satu `Auxheader` kosong pertama untuk kolom `Detail`.
- Mengubah colspan kelompok Bentuk/Metode Pembelajaran dari empat menjadi tiga,
  sesuai tiga kolom data: Metode Pembelajaran, Pembelajaran Luring, dan
  Pembelajaran Daring.
- Jumlah rentang header tetap tepat sepuluh, sama dengan jumlah cell setiap row.

## Verifikasi

- Jalur simpan dan renderer sama-sama memakai key `teknikDanKriteria`.
- Header kosong `Detail` berada sebelum header **Minggu Ke**.
- Kedua source mirror memiliki hash SHA-256 identik.
- `mvn -DskipTests compile`: **BUILD SUCCESS**.

## UAT

1. Buka tab RPS OBE dan bagian Rincian Kurikulum.
2. Ubah satu rincian dan isi **Penilaian (Teknik & Kriteria)**.
3. Simpan dan muat ulang rincian.
4. Pastikan Minggu, CPMK, Indikator, dan Penilaian berada tepat di bawah
   headernya masing-masing.
5. Pastikan isi field tampil pada kolom **Penilaian / Teknik & Kriteria**.
