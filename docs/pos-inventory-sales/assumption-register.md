# Assumption Register — POS Inventory & Sales (varian inventory_sales)

Setiap entri diberi label klasifikasi kebenaran sesuai PERINTAH_MASTER §0.3:
`FACT_SOURCE` / `FACT_MANUAL` / `STRONG_INFERENCE` / `DESIGN_DECISION` / `UAT_REQUIRED`.

| # | Asumsi/Keputusan | Label | Dasar | Dampak jika salah |
|---|---|---|---|---|
| A-01 | Video `Sistem Sales.mp4` dan file analisis video/48-frame TIDAK tersedia lokal (dicari di Downloads 2026-08-11, tidak ditemukan). Sumber visual = PDF/DOCX Panduan v2 + Matriks CSV. | FACT_SOURCE | Glob `*.mp4`/`*Sales*` di C:\Users\USER\Downloads | Detail perilaku runtime legacy yang hanya terlihat di video harus lewat UAT |
| A-02 | Branch kerja AIS = `feat/new-ui-rbac-role-user` (sesuai README paket), zishof-platform = `main`. Kerja dilanjutkan DI BRANCH INI, bukan branch baru (lihat 02-decisions.md D-01). | FACT_SOURCE | `git branch --show-current` kedua repo | — |
| A-03 | Working tree AIS memuat modifikasi asing `PenjadwalanUtil.java` (bukan bagian pekerjaan ini; kemungkinan sesi Codex paralel). File ini TIDAK disentuh/di-commit oleh pekerjaan inventory_sales. | FACT_SOURCE | `git status --short` 2026-08-11 | Commit harus selalu scoped per-file, tidak boleh `git add -A` |
| A-04 | "Penjualan" legacy (layar 30) = customer membeli dari toko → dipetakan ke jalur penjualan/AR existing + Sales Order Lapangan baru; `DraftPembelianAnggotaKoperasi`/`PembelianAnggotaKoperasi` di AIS adalah PENJUALAN TOKO (customer order), bukan procurement. | STRONG_INFERENCE | PERINTAH_MASTER §6.3 + pengalaman kode sesi sebelumnya (checkout kasir memakai entity ini) | Salah mapping = piutang tercatat di ledger yang salah |
| A-05 | "Kulakan/Pembelian Supplier" (layar 20) = procurement → reuse `PengadaanFaktur` + aksi `kulakan_faktur_*` yang sudah ada di server. | FACT_SOURCE | Fitur Kulakan B (task #350-361 sesi sebelumnya, sudah rilis) | — |
| A-06 | Kode legacy dipertahankan sebagai TEKS: supplier 3 karakter, customer 5 karakter, sales 2 karakter, dengan nol di depan dipertahankan. | FACT_MANUAL | Panduan v2 bab 01/04/07 + Matriks CSV | Rekonsiliasi arsip DBF gagal bila kode di-cast ke angka |
| A-07 | `SYARAT_BYR` (termin) supplier legacy menjadi dasar jatuh tempo hutang; field BG/giro (NOMERBG, NAMABANK, TANGGALBG) wajib ada di event pembayaran hutang/piutang. | FACT_MANUAL | Struktur TRAN_HUT.DBF di Panduan v2 | Layar 24-26/34-36 tidak paritas |
| A-08 | Rumus sesi: `HASIL_BERSIH = piutang_dibayar - biaya_sesi - pembayaran_aktual_pembelian`; rekonsiliasi kas terpisah (uang muka + tunai masuk - tunai keluar - setoran). Pembelian KREDIT tidak mengurangi hasil bersih kecuali porsi dibayar/DP. | FACT_MANUAL | ERD §4 + PERINTAH_MASTER §10 | Laporan sesi salah = kepercayaan owner runtuh |
| A-09 | Nomor akun sales legacy (`No. Perkiraan` di layar 07) di-mapping ke COA existing; bila akun tidak ada, field nullable + masuk exception queue. | UAT_REQUIRED | PERINTAH_MASTER §17.8 | — |
| A-10 | "Sales Membawa Nota" legacy (layar 39) tidak terbukti punya penyimpanan permanen di DBF → dimodelkan penuh sebagai SPJ + custody log baru; detail semantik serah-terima dikonfirmasi UAT. | FACT_MANUAL + UAT_REQUIRED | Matriks CSV baris 39 ("penyimpanan permanen legacy belum sepenuhnya terbukti") | — |
| A-11 | Baseline `flutter analyze` = 31 issue (semua info/warning, 0 error); ini kondisi existing SEBELUM pekerjaan inventory_sales dan bukan tanggungan fase ini. | FACT_SOURCE | Run 2026-08-11 (lihat 00-baseline.md) | — |
| A-12 | Password legacy USERS.DBF (field PSW plaintext) TIDAK dimigrasikan; akun baru reset kredensial via Tbmuser existing. | FACT_MANUAL | Panduan v2 §Audit/keamanan | Kebocoran kredensial bila diabaikan |
