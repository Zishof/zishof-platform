# Perbaikan Layout Editor Sub-CPMK

Tanggal: 3 September 2026

## Gejala

Pada modal pendataan CPMK, tabel editor Sub-CPMK hanya memakai bagian kiri
modal. Tombol **Tambah via AI** berada di sisi kanan, sedangkan tabel di bawahnya
memunculkan scrollbar horizontal walaupun masih ada ruang kosong di kanan.

## Penyebab

`reloadFormula()` menempelkan tombol **Tambah Sub-CPMK** dan **Tambah via AI**
langsung ke `Row` milik grid. Pada ZK, setiap child langsung dari `Row` menjadi
cell. Grid kemudian membentuk dua kolom. Baris editor berikutnya hanya memiliki
satu cell, sehingga wrapper tabel ditempatkan pada kolom pertama saja.

## Perbaikan

- Kedua tombol dipindahkan ke satu `Div` toolbar di dalam satu cell.
- Toolbar memakai flex dan dapat membungkus pada layar sempit.
- Wrapper tabel ditegaskan memakai `width:100%`, `max-width:100%`, dan
  `box-sizing:border-box`.
- Scrollbar horizontal dipertahankan hanya sebagai fallback ketika lebar layar
  lebih kecil daripada lebar minimum empat kolom editor.

Dengan struktur ini, tombol AI tidak lagi membentuk kolom tersendiri dan tabel
Sub-CPMK dapat menggunakan seluruh ruang modal.

## Verifikasi

- Kedua source mirror mempunyai hash SHA-256 identik.
- `mvn -DskipTests compile`: **BUILD SUCCESS**.

## UAT

1. Buka data CPMK yang mempunyai satu atau lebih Sub-CPMK.
2. Pastikan tombol **Tambah Sub-CPMK** dan **Tambah via AI** tampil bersebelahan
   di baris toolbar.
3. Pastikan kolom Kode, Sub-CPMK, Bobot, dan Hapus terlihat selebar area modal.
4. Pastikan tidak ada ruang kanan kosong akibat tombol AI.
5. Perkecil jendela dan pastikan scrollbar horizontal tetap dapat dipakai tanpa
   menutupi data.
