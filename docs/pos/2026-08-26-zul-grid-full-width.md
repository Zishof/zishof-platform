# Normalisasi Grid/Tabel ZUL Full Width

Tanggal: 26 Agustus 2026

## Tujuan

Merapikan seluruh pola tabel data ZUL agar memenuhi lebar kontainer dan tidak
menyisakan pita/kolom kosong di sisi kanan, tanpa merusak grid formulir yang
memang menggunakan kolom kosong sebagai pasangan label dan input.

## Implementasi

- `MyGrid` tetap memakai kelas bawaan `dgrid`. Lebar penuh ditangani oleh
  aturan `.dgrid.z-grid` yang sudah tersedia di `css_utama.css`, sehingga
  constructor tidak menimpa kalkulasi ukuran milik ZK.
- Aturan tambahan yang memaksa elemen internal header/body/footer menjadi
  `display:block`, `width:100%`, dan `overflow:auto` telah ditarik kembali.
  Pada ZK lama aturan tersebut mengganggu kalkulasi virtual row: jumlah data
  dan paging tampil, tetapi tinggi baris membesar dan isi sel seolah hilang.
- Tabel yang benar-benar lebih lebar dari layar menggunakan gulir horizontal
  melalui aturan responsif yang telah ada, tanpa mengubah struktur renderer.
- Normalisasi `UIHelper.absorptionKebab()` yang sudah tersedia tetap menangani
  kolom aksi trailing dan menyembunyikan kolom sisa kanan yang benar-benar
  kosong setelah tombol aksi diserap ke menu kebab.

## Batas pengamanan

Tidak dilakukan penggantian massal `label=""` di seluruh ZUL. Banyak pemakaian
tersebut merupakan kolom aksi, spacer formulir, atau bagian layout yang sah.
Perbaikan dipusatkan pada komponen dan kelas tabel data bersama agar cakupannya
luas tetapi tetap aman.

## Verifikasi regresi MyGrid

- Kedua mirror `ais.ui.util.MyGrid` memiliki checksum yang identik.
- Keduanya berhasil dikompilasi memakai `-source 1.6 -target 1.6`.
- Struktur CSS seimbang dan blok normalisasi agresif tidak lagi tersedia.
- Paging serta model tidak diubah; koreksi hanya memulihkan perhitungan ukuran
  baris bawaan ZK agar isi sel kembali dirender.
- Koreksi sumber ada di SVN **r78288** dan catatan server di **r78298**.
- UAT visual lokal belum dijalankan pada 2 September 2026 karena tidak ada
  instance Tomcat lokal yang sedang aktif; hasil kompilasi tidak boleh disebut
  sebagai pengganti UAT visual.

## Aturan batch lintas sesi

Setiap batch berikutnya harus ditutup dengan verifikasi yang sesuai risikonya,
catatan di `docs/pos/`, commit SVN untuk sumber server/ZK, serta commit dan push
Git untuk sumber Flutter/Desktop atau catatan mirror yang memang relevan.
Perubahan sesi lain tidak boleh ikut dimasukkan ke commit.
