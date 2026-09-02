# Tombol Hapus pada Detail Tugas Kelompok

Tanggal: 2 September 2026

## Laporan dan akar masalah

Catur STTIF melaporkan panel Pengaturan Tugas Kelompok tidak menyediakan tombol
hapus. Handler lama masih ada di toolbar/menu `...`, tetapi tidak ikut dipasang
ketika panel kartu baru dibuat.

## Perbaikan server ZK

Panel sekarang memiliki tombol merah **Hapus Tugas Kelompok**. Tombol toolbar
lama dan tombol baru memakai satu handler konfirmasi. Haknya tetap dijaga oleh
`bolehKelola(...)`; peserta didik tidak melihat panel pengaturan.

Sumber kanonis berada di working copy SVN AIS:

- `ais/action/master/helper/TugasKelompokHelper.java` pada kedua mirror source;
- catatan rinci `docs/pos/75-tombol-hapus-tugas-kelompok.md`.

## Verifikasi

- kompilasi target Java 7: lulus;
- mirror source: identik;
- satu operasi hapus dipakai oleh dua tombol melalui handler bersama;
- UAT visual menunggu rebuild/deploy web ECAMPUS.

Repository Git ini hanya menerima catatan mirror karena source ZK tidak berada
di repository Flutter/Desktop.
