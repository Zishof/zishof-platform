# Paket UAT E2E Apotik — 8 September 2026

Paket ini berisi rerun UAT live setelah deployment UI modern Apotik v1.35.1 build 189. Status akhir: **PASS DENGAN OBSERVASI**.

## Dokumen utama

- `DOKUMEN-UAT-E2E-APOTIK-2026-09-08.docx`
- `DOKUMEN-UAT-E2E-APOTIK-2026-09-08.pdf`
- `USER-MANUAL-E2E-APOTIK-2026-09-08.docx`
- `USER-MANUAL-E2E-APOTIK-2026-09-08.pdf`
- `LAPORAN-UAT-E2E-APOTIK-2026-09-08.md`
- `CHECKSUMS-SHA256.txt`

## Struktur bukti

- `evidence/screenshots-modern-ui/`: viewport 1920, 1366, 768, dan 390 px.
- `evidence/screenshots-kasir-live/`: lima mode kasir dan Tebus Resep mobile.
- `evidence/screenshots-pengadaan/`: PR sampai pembayaran vendor dan laporan pembelian.
- `evidence/screenshots-akuntansi-submenu/`: posting dan master akuntansi.
- `evidence/screenshots-akuntansi-jurnal/`: verifikasi jurnal run-specific terposting.
- `evidence/screenshots-akuntansi-laporan/`: enam laporan akuntansi inti.
- `evidence/results/`: hasil mesin dan provenance baseline.
- `assets/`: ERD dan flow diagram.

## Provenance

Transaksi mutatif 100 data per proses telah dijalankan dan diposting pada 7 September 2026. Rerun 8 September bersifat read-only dan memverifikasi deployment, navigasi, status run-specific, laporan, serta responsivitas tanpa membuat transaksi baru.

## Verifikasi akhir

- Full regression: 1.073/1.073 PASS.
- Flutter analyze: exit code 0; hanya 51 temuan level `info` non-blocking.
- PDF UAT 52 halaman dan User Manual 41 halaman telah dirender penuh untuk QA visual.
- Tidak ada penanda screenshot/bukti yang hilang pada kedua DOCX.
