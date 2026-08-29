# Fase E — MTO (Make-To-Order) dan QC Hasil Produksi

Tanggal: 29 Agustus 2026  
Status: server + Flutter **lulus** (TesFaseEMtoQc 17/17 di DB UAT;
TesFaseCReorder tetap 19/19 pasca-refactor; Flutter 511/511); belum di-commit  
Rujukan: SVN `docs/pos/55-fase-e-mto-dan-qc.md` (keputusan lengkap + batas
fase), dok. 48 §4 Fase 5/6

Dengan fase ini **seluruh peta jalan dok. 48/49 (Fase 0, A, B, C, D, E)
terlaksana** dan terbukti di DB UAT.

## Ringkas

- **MTO**: rute produk diperluas `MTO_BELI`/`MTO_PRODUKSI`. Konfirmasi
  Sales Order lapangan (DRAFT→PESAN) — dan HANYA itu, sesuai dok. 48 §6
  no. 3 — memicu draf WO (lewat mesin bersama `buatWoDrafOtomatis`, satu
  mesin dengan penjadwal ambang Fase C) atau pengajuan pembelian ber-`so_id`
  lewat Gudang Pemasok toko. Idempoten dua-duanya; berjalan di dalam
  transaksi konfirmasi.
- **QC**: `Produk.perluQc` baru. OUTPUT POSTED produk QC menerbitkan dokumen
  **Quality Alert** (jenis `QC`, menumpang infra dokumen produksi) dan
  mengkarantina `ProdukBatch` ber-lot sama (mesin karantina yang sudah ada,
  koreksi dok. 49 §1.2). Disposisi `REWORK`/`UNBUILD`/`SCRAP`/`RELEASE`
  membuat dokumen turunan lewat mesin fase sebelumnya (WO / UNBUILD Fase D /
  WASTE Fase 0) dan mengelola karantina. Jurnal per disposisi menunggu
  pemetaan akun pemilik — batas fase yang disengaja, bukan setengah jadi.

## Sisi Flutter (repo ini)

- `models.dart`: `Produk.perluQc` (+ `rute` menampung nilai MTO).
- `produk_screen.dart`: kontrol rute berubah dari 2 segmen menjadi
  **dropdown 4 pilihan** (Beli / Produksi Sendiri / MTO Beli / MTO
  Produksi) + **saklar "Perlu QC saat hasil produksi"**; payload
  `produk_simpan` membawa `rute` + `perlu_qc`.
- `produksi_screen.dart`: bagian baru `qualityAlert` (jenis
  `quality_alert`, "Quality Alert (QC)"); di rincian dokumen QC DRAFT,
  tombol Setujui generik diganti **empat tombol disposisi** yang memanggil
  `produksi_qc_disposisi`.
- `app_shell.dart`: menu "Quality Alert (QC)" di grup Produksi (kunci izin
  `produksi_quality_alert`).
- `test/mto_qc_kontrak_test.dart` (baru, 3 uji): kompatibilitas katalog
  lama (rute kosong, QC false) dan pemetaan nilai server.

## Bukti

- `TesFaseEMtoQc` 17/17 (DB UAT; refleksi ke fungsi persis yang dipanggil
  alur konfirmasi SO / posting OUTPUT / endpoint disposisi): WO MTO planned
  7 ber-BOM; pengajuan `so_id` qty 4; idempoten; Quality Alert + karantina +
  mutasi batch; SCRAP → WASTE draf; UNBUILD → prefill komponen BOM ter-skala;
  RELEASE → karantina diangkat; produk non-QC tak tersentuh.
- `TesFaseCReorder` diulang pasca-ekstraksi mesin WO: 19/19 — refactor tidak
  mengubah perilaku penjadwal ambang.
- `javac 1.7` EXIT=0; Flutter suite penuh **511 lulus / 0 gagal**; analyze
  bersih di berkas tersentuh.
