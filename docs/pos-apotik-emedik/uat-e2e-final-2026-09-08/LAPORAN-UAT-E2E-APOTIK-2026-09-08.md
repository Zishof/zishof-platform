# Laporan UAT End-to-End Apotik — 8 September 2026

## Putusan

**PASS DENGAN OBSERVASI.** Alur inti Kasir Apotik → Kulakan → Pembayaran Vendor → Posting → Laporan berjalan end-to-end. Batch transaksi mutatif 7 September 2026 telah menyelesaikan minimal 100 data per proses. Rerun 8 September 2026 memverifikasi deployment secara live dan read-only agar tidak menggandakan transaksi atau jurnal yang sudah final.

## Identitas rilis

- Server: `https://demo.ecampus.id/ecampus`
- Aplikasi: `1.35.1 (build 189)`
- Frontend: `676d5b2edee3f4b1fcec2880bb793610452c1851`
- Metode rerun: Flutter integration test pada Windows, koneksi live, tanpa mutasi transaksi.

## Hasil utama

| Area | Volume / hasil | Status |
|---|---:|---|
| OTC / Obat Bebas | 100 transaksi baseline; 100 produk live dari total 11.000 | PASS |
| Resep Dokter | 100 transaksi baseline; 100 resep live; 1.000 resep klinis sample | PASS |
| Racikan | 100 transaksi baseline; 500 formula | PASS |
| Produksi Farmasi | 100 produksi baseline; 500 formula | PASS |
| Tebus Resep | 100 transaksi campuran baseline; 100 resep live | PASS |
| Responsif | 1920, 1366, 768, 390 px; Tebus Resep terlihat di mobile | PASS |
| Pengadaan | 100 PR, PO, BAST, tagihan, dan pembayaran baseline | PASS |
| Posting | 400 Penjualan + 400 HPP + 100 BAST + 100 Bayar Vendor + 100 Jurnal Umum | PASS |
| Idempotensi | 1.100 jurnal run-specific; retry membuat 0 duplikasi | PASS |
| Laporan | Penjualan, pembelian, Laba Rugi, Neraca, Arus Kas, Jurnal, Buku Besar, Neraca Saldo | PASS |

## Data live yang diregresi 8 September

- Pengadaan: 264 PR, 254 PO, 255 BAST, 255 tagihan.
- BAST: seluruh 255 disetujui dan masuk stok.
- Katalog laporan: 63 laporan dalam 5 halaman.
- Posting Kulakan run-specific: 100/100 terposting, 0 siap.
- Posting Bayar Hutang run-specific: 100/100 terposting, 0 siap.
- Enam laporan akuntansi inti berhasil ditampilkan.
- Jurnal `UAT-APT-E2E-FINAL-20260907-JU` ditemukan dengan status `Terposting`; layar Jurnal Umum memakai fallback salinan lokal, sementara laporan Keseluruhan Jurnal live berhasil dimuat.

## Verifikasi kode dan artefak

- Full regression Flutter: **1.073/1.073 PASS** (`flutter test --no-pub test`).
- Flutter analyze: selesai dengan exit code 0; 0 error, 0 warning, dan 51 temuan level `info` non-blocking pada codebase bersama.
- DOCX terverifikasi: UAT 266 paragraf, 54 tabel, 50 gambar; User Manual 395 paragraf, 42 tabel, 39 gambar; 0 penanda bukti hilang.
- PDF final terverifikasi secara visual: UAT 52 halaman dan User Manual 41 halaman; seluruh halaman dirender dan diperiksa.

## Observasi

1. Ada 3.600 draft HPP/Penjualan historis global yang tertahan karena transaksi pembayaran lama tidak ada atau bernilai nihil. Data ini bukan bagian batch UAT final dan tidak diposting paksa.
2. Posting Terima Piutang belum memiliki endpoint khusus Apotik. Kondisi ini tidak dipakai pada skenario tunai dan pembelian vendor yang diuji, sehingga berstatus N/A, bukan PASS.
3. Akun Laba Ditahan belum diatur pada master Toko. Preview Tutup Buku tersedia, tetapi proses tidak dapat diselesaikan sebelum konfigurasi ini dilakukan.
4. Closing tidak dijalankan karena irreversible dan memerlukan mandat pemilik data.
5. Layar Jurnal Umum masih menampilkan penanda salinan lokal setelah tiga kali reload. Status posting tetap tervalidasi oleh baseline API run-specific dan laporan Keseluruhan Jurnal live; endpoint daftar jurnal perlu diperiksa untuk menghilangkan fallback.

## Batas validasi

- Screenshot formulir PR, PO, BAST, dan transaksi diambil tanpa menekan tombol simpan/proses pada rerun 8 September.
- Bukti mutatif dan idempotensi berasal dari batch UAT terisolasi 7 September, disalin ke paket ini dengan nama `baseline-20260907-*.json`.
- Draft historis global dan periode lain tidak disentuh.

## Artefak

- `DOKUMEN-UAT-E2E-APOTIK-2026-09-08.docx/.pdf`
- `USER-MANUAL-E2E-APOTIK-2026-09-08.docx/.pdf`
- `evidence/screenshots-*`
- `evidence/results/`
- `evidence/results/flutter-test-full-20260908.log`
- `evidence/results/flutter-analyze-20260908.log`
- `assets/` (ERD dan flow diagram)
