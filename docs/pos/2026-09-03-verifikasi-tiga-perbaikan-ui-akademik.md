# Verifikasi Tiga Perbaikan UI Akademik

Tanggal: 3 September 2026

Dokumen ini menggabungkan audit ulang tiga laporan pengguna: layout editor
Sub-CPMK, kolom Penilaian RPS OBE, dan duplikat status Nonaktif pada filter
Mahasiswa.

## 1. Editor Sub-CPMK hanya memakai sisi kiri

### Penyebab

Tombol **Tambah Sub-CPMK** dan **Tambah via AI** sebelumnya ditempel langsung
ke `Row`. ZK memperlakukan setiap child langsung sebagai cell, sehingga grid
membentuk dua kolom. Baris editor berikutnya hanya mempunyai satu cell dan
akhirnya dibatasi pada kolom kiri.

### Kondisi setelah perbaikan

- Kedua tombol berada dalam satu `Div` toolbar/cell.
- Wrapper editor memakai lebar penuh dan `box-sizing:border-box`.
- Scroll horizontal hanya menjadi fallback pada layar sempit.
- Revisi kode: SVN r83527.

## 2. Kolom Penilaian terlihat kosong

### Penyebab

Nilai Penilaian tidak hilang. Field disimpan dan dirender menggunakan key JSON
yang sama, `teknikDanKriteria`. Masalahnya adalah `Auxhead` tidak menyediakan
header kosong untuk kolom pertama yang dipakai komponen ZK `Detail`. Semua
judul bergeser satu cell ke kiri; nilai CPMK `== Belum Ditentukan ==` tampak
seolah berada di bawah Penilaian dan nilai Penilaian terdorong ke kanan.

### Kondisi setelah perbaikan

- Header kosong untuk cell `Detail` sudah ditambahkan.
- Colspan kelompok pembelajaran diselaraskan dari empat menjadi tiga.
- Jalur field -> JSON -> renderer -> `Pertemuan.tugasDanPenilaian` tetap utuh.
- Revisi kode: SVN r83531.

Catatan: `== Belum Ditentukan ==` memang berarti CPMK pada rincian tersebut
belum dipilih; setelah alignment benar, teks itu tampil pada kolom CPMK.

## 3. Status Nonaktif tampil dua kali

### Penyebab

Database lama mempunyai lebih dari satu entity `StatusMahasiswa` dengan kode
EPSBED `N`. Helper combo menampilkan semua entity karena ID-nya berbeda.

### Kondisi setelah perbaikan

- Pilihan dideduplikasi berdasarkan kode semantik, sehingga hanya satu
  **Nonaktif - N** yang tampil.
- Filter dan renderer membandingkan kode semantik, dengan ID sebagai fallback.
- Satu pilihan tetap mencakup riwayat yang merujuk seluruh ID duplikat lama.
- Tidak ada data master yang dihapus.
- Revisi kode: SVN r83534.

## Verifikasi gabungan

- Ketiga pasangan `src/main/java` dan `src/main/src` memiliki SHA-256 identik.
- Invariant struktur toolbar, key `teknikDanKriteria`, alignment header, serta
  filter status semantik: **lulus**.
- Helper deduplikasi ditemukan pada bytecode hasil kompilasi.
- `mvn -DskipTests compile`: **BUILD SUCCESS**.

## Balasan WhatsApp

Assalamu'alaikum, terima kasih informasinya. Ketiga poin sudah kami cek ulang
sampai ke alur kodenya dan sudah diperbaiki:

1. Tabel Sub-CPMK sebelumnya hanya memakai sisi kiri karena tombol Tambah dan
   tombol AI terbentuk sebagai dua kolom terpisah. Sekarang tombol disatukan
   dalam satu toolbar dan tabel memakai lebar area secara penuh.
2. Data Penilaian sebenarnya sudah tersimpan. Yang bermasalah adalah posisi
   header tabel bergeser satu kolom karena kolom Detail belum diperhitungkan.
   Header sudah diselaraskan sehingga nilai Penilaian tampil di kolom yang
   tepat. Tulisan "Belum Ditentukan" merupakan status CPMK yang belum dipilih,
   bukan isi Penilaian.
3. Status Nonaktif ganda berasal dari dua data master lama dengan kode yang
   sama. Pilihan sudah digabung menjadi satu tanpa menghapus data lama, dan
   hasil filter tetap mencakup seluruh mahasiswa Nonaktif.

Build gabungan sudah berhasil. Perubahan perlu masuk deployment/restart server,
setelah itu mohon dibantu cek ulang pada tiga layar tersebut. Terima kasih.
