# 72. Blokir Kolom Kredensial dari Endpoint SQL Klien — Tanpa Syarat

Tanggal: 2 September 2026  
Lanjutan langsung: dok. 70 (permukaan SQL klien), dok. 71 (tulis anonim ditutup)  
Sifat: penguatan keamanan lapis dasar

## Celah yang tersisa sesudah dok. 71

Dok. 71 menutup SQL **tulis** anonim, tetapi jalur **baca** (`action=sql`)
sengaja dibiarkan dapat dipanggil tanpa login karena beberapa halaman publik yang
sah memakainya. Perlindungan atas jalur baca bergantung pada `SqlSecurityGuard`,
yang modenya bawaan `off`.

Konsekuensinya, pada instalasi yang belum menyetel mode: endpoint `/Data` masih
dapat dipakai membaca **kolom kata sandi** — kombinasi paling berbahaya dari
seluruh rantai temuan ini.

## Yang diperbaiki

Akses kolom kredensial — `userpassword`, `password`, `sandi` — kini diblokir
**SELALU**, apa pun modenya, pada jalur baca maupun tulis.

Tiga sifat yang membuat blokir ini aman dijadikan dasar:

1. **Tidak membaca konfigurasi.** Memakai daftar tertanam, bukan
   `daftar_token_terlarang_sql`. Maka ia berlaku bahkan saat mode `off`, tidak
   menambah I/O pada jalur panas, dan tidak terkena masalah pembacaan konfigurasi
   yang di sebagian jalur terbukti dapat menggantung (dok. 67 §4).
2. **Berjalan lebih dulu** dari pemeriksaan berbasis mode, sehingga tidak dapat
   dilewati dengan mematikan mode.
3. **Memasking literal string lebih dulu**, sehingga nama produk seperti
   "Kata Sandi Board Game" tidak salah tertolak.

Daftar `daftar_token_terlarang_sql` yang dapat diperluas admin (mis. tabel gaji)
tetap ada dan tetap berlaku hanya pada mode aktif — blokir kredensial ini adalah
lantai keamanan minimum di bawahnya, bukan penggantinya.

## Dampak: nol fungsi terputus

Penyisiran seluruh JSP: **tidak ada satu pun** halaman yang mengirim SQL
menyentuh kolom-kolom itu. Diverifikasi pula tidak ada `action=sql` yang memuat
substring `sandi`/`password` dalam kuerinya, sehingga tidak ada false-positive.
`SELECT userid FROM tbmuser` (mis. cek keunikan saat registrasi member) tetap
lolos karena hanya nama tabel, bukan kolom kredensial.

## Bukti

`SqlSecurityGuardSelfTest` — **20/20 lulus**, tanpa basis data, termasuk:

- `SELECT userpassword`, `SELECT password`, `UPDATE userpassword`, `SELECT sandi`
  semuanya ditolak;
- `SELECT userid, nama FROM tbmuser` tetap lolos (tidak over-block);
- kata "sandi" di dalam literal string tidak salah tertolak.

## Rangkuman rantai keamanan endpoint SQL (dok. 70–72)

| Lapis | Berlaku | Status |
| --- | --- | --- |
| Tulis anonim ditutup | selalu | aktif (dok. 71) |
| Kolom kredensial diblokir | selalu | aktif (dok. 72) |
| Read-only + tolak DDL + objek sistem | saat mode `log`/`enforce` | menunggu pemilik menyalakan (dok. 70) |
| Operasi tulis pindah ke endpoint ber-aksi | — | keputusan jangka panjang (dok. 70) |
