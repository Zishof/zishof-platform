# Ringkasan UAT POS Apotik v1.34.22

Keputusan: **LULUS BERSYARAT** untuk pilot terkontrol. Seluruh status berikut membedakan bukti transaksi, bukti komponen, dan integrasi yang masih terblokir.

| Area | Hasil | Bukti utama |
|---|---:|---|
| Penjualan obat jadi | 50/50 PASS | transaksi API + kasir + laporan |
| Penebusan racikan | 50/50 PASS | transaksi API + 100 resep terbaca |
| Penerimaan PBF | PASS | 150 unit, 1 batch baru |
| PR | 50 PASS API | dashboard/form/daftar |
| PO | 50 PASS API | termin dan non-termin |
| BAST | 50 PASS API | dashboard/form/daftar |
| Terima tagihan | 50 PASS API | dashboard/daftar |
| Pembayaran vendor | 50 PASS API | disetujui |
| Proses Transfer | PASS | ID 10, 50 detail, Rp45.730.000 |
| Jurnal vendor manual | 50 PASS | seimbang, terposting, idempoten |
| Enam layar laporan | PASS UI | angka masih perlu rekonsiliasi owner |
| Layar farmasi multi-monitor | PASS KOMPONEN | 50 data tersamar; endpoint demo belum terdeploy |
| Katalog volume | BLOCKED ENV | demo 2 item; generator 1.000 belum terdeploy |
| Jurnal otomatis | BLOCKED | preview server belum tersedia |
| Kulakan generik | BLOCKED ROLE | akun demo tidak memiliki toko |
| Android production signing | BLOCKED OWNER | keystore belum tersedia |

Dokumen lengkap, screenshot, diagram, risiko, dan kriteria retest tersedia dalam Manual Pengguna dan Laporan UAT pada release yang sama.
