# Paket UAT dan User Manual AB Chicken POS Desktop

Paket ini merupakan bukti pelaksanaan UAT end-to-end tenant `abchiken` pada 9 September 2026. Seluruh
langkah operasional dilakukan melalui POS Desktop Windows varian `abchicken`. UAT awal menggunakan
versi 1.34.27 build 190 dan telah diregresi ulang pada kandidat rilis 1.34.30 build 193.
Aplikasi Web dibatasi untuk registrasi tenant, konfigurasi administratif, pemantauan, dan audit oleh
admin utama.

## Artefak utama

- `User-Manual-dan-UAT-E2E-AB-Chicken-POS-Desktop-2026-09-09.docx` — manual editable 74 halaman.
- `User-Manual-dan-UAT-E2E-AB-Chicken-POS-Desktop-2026-09-09.pdf` — versi distribusi yang telah
  diperiksa visual per halaman.
- `07-hasil-uat-pos-desktop-e2e-20260909.md` — ringkasan eksekusi, hasil, dan catatan operasional.
- `08-hasil-verifikasi-kandidat-rilis-v1.34.30.md` — adendum regresi kandidat rilis dan bukti isolasi kanal.
- `diagrams/` — use case, flowchart, ERD/aliran data, dan relasi akun posting.
- `evidence/screenshots-asli/` — tangkapan layar asli hasil UAT.
- `evidence/screenshots-beranotasi/` — tangkapan layar yang sudah diberi kotak, nomor, dan panah.
- `evidence/hasil-otomasi/` — hasil gate data, aksi, dan laporan dalam CSV.
- `evidence/scripts/` — tiga integration test yang dapat dijalankan ulang.
- `evidence/release-candidate-1.34.30/` — tangkapan layar dan CSV hasil regresi versi 1.34.30+193.
- `SHA256SUMS.txt` — checksum artefak utama, diagram, hasil otomatis, dan script reproduksi.

## Status ringkas

| Gate | Hasil |
|---|---|
| Kontrak POS Desktop | LULUS, 33/33 |
| Data dan integritas tenant | LULUS, 19/19 |
| Aksi siklus operasional | LULUS, 10/10 |
| Laporan akuntansi | LULUS, 6/6 |

Regresi kandidat rilis juga LULUS: kontrak aplikasi 23/23, isolasi updater 7/7, data settle 13/13,
aksi end-to-end 10/10, dan laporan 6/6. Keseluruhan Jurnal serta Buku Besar masing-masing menampilkan
608 baris setelah siklus transaksi baru membentuk jurnal 307–312.

Saldo awal kas/bank pilot belum dimuat. Karena itu, laporan Arus Kas menghitung saldo akhir negatif
secara aritmetis meskipun penelusuran jurnalnya benar. Masukkan saldo awal sebelum pilot dijadikan
pembukuan produksi.

## Reproduksi

Salin script yang diperlukan dari `evidence/scripts/` ke folder `integration_test/` aplikasi Desktop,
kemudian jalankan dengan build varian `abchicken`. Gunakan periode laporan 1–30 September 2026 agar
seluruh jurnal data contoh tercakup. Script aksi mengubah status dan membentuk jurnal; jalankan hanya
pada tenant UAT yang memang disiapkan untuk pengujian.
