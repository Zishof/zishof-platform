# Indikator Klik Rincian Semester Mahasiswa

Tanggal: 3 September 2026

## Laporan

Angka semester pada kolom **Status/Awal/Smt** sebenarnya dapat diklik untuk
membuka analisis asal angka semester. Namun, tampilan sebelumnya hanya berupa
angka biru kecil bergaris bawah sehingga mudah dianggap sebagai teks biasa.

## Perbaikan

Affordance klik dipusatkan pada
`SemesterMahasiswaAnalisisPopupHelper.pasangLink(...)`:

- label menjadi **Semester n · klik**;
- tautan diberi bentuk pill biru, border, garis bawah, dan cursor pointer;
- tooltip menyebut semester yang dibuka serta isi rinciannya;
- listener dan query analisis tetap lazy, baru berjalan setelah pengguna klik.

Karena renderer seluruh baris dan seluruh halaman pagination Mahasiswa selalu
memanggil helper tersebut, indikator yang sama berlaku untuk setiap tampilan
angka semester yang menyediakan popup analisis, bukan hanya baris pada gambar
laporan.

## Dampak dan batasan

- Tidak ada perubahan rumus semester, data KRS, status mahasiswa, atau database.
- Klik tetap membuka popup **Analisis Semester Mahasiswa** yang sama.
- Tampilan semester lain yang hanya berupa input/filter dan memang tidak
  mempunyai aksi analisis tidak diubah menjadi tautan palsu.

## Verifikasi

- Kedua mirror `src/main/java` dan `src/main/src` identik.
- `mvn -DskipTests compile`: **BUILD SUCCESS**.

## Catatan deployment

Perubahan berada pada Java server/ZK. Deploy WAR atau class hasil build lalu
restart/reload aplikasi agar tampilan baru terbaca oleh sesi pengguna.

