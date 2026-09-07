# Release Checklist Paket UAT E2E Apotik

Tanggal verifikasi: 7 September 2026

Lingkungan: `https://demo.ecampus.id/ecampus/`

Rilis aplikasi: Apotik `1.35.1+189`

Backend tervalidasi: SVN `r87376`
Status: **SIAP DIPUBLIKASIKAN**

## Cakupan UAT

- Kasir Apotik: OTC, Resep Dokter, Racikan, Produksi Farmasi, dan Tebus Resep, masing-masing 100 transaksi/proses.
- Kulakan: PR, PO, BAST, Terima Tagihan, dan Pembayaran Vendor, masing-masing 100 dokumen/item.
- Akuntansi: posting jurnal Penjualan, HPP, BAST/persediaan, pembayaran vendor, dan 100 Jurnal Umum UAT.
- Laporan: penjualan, pembelian, Laba Rugi, Neraca, Arus Kas, Jurnal Umum, Buku Besar, dan Neraca Saldo.

## Hasil akhir

- Live API UAT: PASS.
- Total proses kasir: 500 PASS.
- Total dokumen procurement: 500 PASS.
- Total jurnal run-specific terposting: 1.100.
- Draf run-specific setelah posting: 0.
- Retry transaksi/jurnal baru: 0.
- Flutter test: 1.058/1.058 PASS.
- Flutter analyze: 0 error dan 0 warning; 51 informational lint historis.

## Verifikasi artefak

- Word: 116 halaman, 131 gambar, 0 halaman kosong, dan audit aksesibilitas 0 high/medium/low.
- PDF: 116 halaman, seluruh halaman dapat dirender dan teks dapat diekstrak.
- PowerPoint: 18 slide, first-party import PASS, package integrity 0 temuan, layout 0 temuan dan 0 warning, serta seluruh slide dirender dan diperiksa satu per satu.
- Bukti: 32 screenshot dan 7 ringkasan JSON.

Catatan lingkungan lokal: PowerPoint menampilkan status aktivasi produk saat percobaan ekspor otomatis. Karena itu, validasi PPTX mengandalkan pemeriksaan struktur, first-party import, dan render ulang seluruh 18 slide. Tidak ada klaim pengujian native PowerPoint di luar validasi tersebut.

## Risiko dan rollback

- Tidak ada migrasi database dalam commit dokumentasi ini.
- Tidak ada perubahan source aplikasi yang dimasukkan ke commit publikasi UAT.
- Rollback publikasi dilakukan dengan `git revert` terhadap commit dokumentasi.
- UAT harus dijalankan ulang bila skema database, posting, pembayaran, formula, batch, atau kontrak API berubah.

## Artefak publikasi

- `Manual-UAT-E2E-Apotik-Pengadaan-Akuntansi-2026-09-07.docx`
- `Manual-UAT-E2E-Apotik-Pengadaan-Akuntansi-2026-09-07.pdf`
- `Presentasi-UAT-E2E-Apotik-2026-09-07-final.pptx`
- `LAPORAN-UAT-E2E-APOTIK-2026-09-07.md`
- `CHECKSUMS-SHA256.txt`
- `assets/`
- `evidence/`
