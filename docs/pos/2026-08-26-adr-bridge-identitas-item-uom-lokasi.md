# ADR: Bridge identitas item, UOM, dan lokasi lintas domain

Tanggal: 26 Agustus 2026

## Status

**Diterima untuk kontrak aplikasi.** Implementasi skema fisik, backfill, dan
cutover database masih menunggu hasil preflight pada salinan/staging database.
Keputusan ini tidak memberikan izin menjalankan DDL/DML pada produksi.

## Context

Sistem existing memakai beberapa model yang sah tetapi berasal dari domain
berbeda:

- `koperasi.produk` melalui `ais.database.model.inventory.Produk`;
- `asset.master_asset` melalui `ais.database.model.asset.MasterAsset`;
- item medis/logistik pada domain SIRS;
- `koperasi.toko`, `sirs.gudang`, dan `asset.lokasi` sebagai sumber lokasi;
- satuan produk, satuan master asset, dan konversi medis yang tidak mempunyai
  kontrak generik tunggal.

Nilai ID numerik pada tabel-tabel tersebut dapat sama tanpa menunjuk objek yang
sama. Menyamakan ID secara langsung akan membuat PR, PO, BAST, pergudangan,
produksi, dan POS berpotensi membaca barang atau lokasi yang keliru. Mengganti
seluruh model lama sekaligus juga berisiko memutus fungsi existing.

## Decision

1. Identitas item menggunakan referensi bertipe yang terdiri dari
   `tenantKey`, `sourceType`, `sourceId`, dan `sourceScopeId` opsional.
2. `sourceType` wajib eksplisit. Tipe awal yang didukung adalah
   `KOPERASI_PRODUK`, `ASSET_MASTER_ASSET`, dan `SIRS_ITEM`.
3. Identitas lokasi menggunakan pola yang sama dengan tipe awal
   `KOPERASI_TOKO`, `SIRS_GUDANG`, `ASSET_LOKASI`, dan `WAREHOUSE_BIN`.
4. Kesamaan ID numerik, kode, barcode kosong, atau nama tidak pernah cukup untuk
   menggabungkan dua record lintas domain.
5. Penyamaan ke item/lokasi kanonis dilakukan hanya oleh resolver/adaptor yang
   dapat diaudit. Relasi existing eksplisit, misalnya `Produk.masterAsset`, boleh
   menjadi kandidat mapping; hasil ambigu wajib masuk rekonsiliasi manual.
6. Konversi satuan menggunakan rasio `BigDecimal` positif
   `nilaiTujuan = nilaiSumber * numerator / denominator`, dengan scale dan
   rounding mode eksplisit. Konversi balik merupakan bagian dari UAT.
7. Kontrak aplikasi awal diwujudkan oleh:
   - `InventoryItemReference`;
   - `InventoryLocationReference`;
   - `InventoryUomConversion`;
   - `InventoryIdentityResolver`.
8. Kontrak ditempatkan identik pada dua mirror source server dan tetap kompatibel
   Java 1.7/gaya Java 1.6.

## Consequences

### Positif

- Tidak ada collision tersembunyi antara ID Produk, MasterAsset, item SIRS,
  Toko, Gudang, Lokasi, atau Bin.
- Model lama tetap berfungsi selama migrasi additive.
- Writer ledger berikutnya dapat menerima identitas kanonis tanpa mengetahui
  detail tabel sumber.
- Konversi satuan dapat diuji deterministik dan tidak bergantung pada tipe
  floating point.
- Audit dan rekonsiliasi dapat menunjukkan sumber asli setiap mapping.

### Negatif dan biaya

- Semua adaptor PR/PO/BAST/WMS/POS perlu membawa discriminator sumber.
- Diperlukan tabel bridge, backfill, index, cache resolver, dan antrean mapping
  ambigu sebelum cutover.
- Query lintas domain menjadi sedikit lebih panjang selama masa dual reference.
- Kesalahan data lama tidak boleh ditebak otomatis sehingga sebagian mapping
  memerlukan keputusan operator.

## Alternatives considered

### Mengganti seluruh tabel item dengan satu tabel baru

Ditolak untuk fase awal karena blast radius terlalu besar dan dapat memutus
modul Asset, Koperasi, SIRS, Pengadaan, dan POS sekaligus.

### Menganggap ID numerik yang sama sebagai item/lokasi yang sama

Ditolak karena ID hanya unik di tabel sumbernya dan telah terbukti dapat
bertabrakan lintas domain.

### Menyamakan berdasarkan nama atau barcode

Ditolak sebagai kunci integritas. Nama dapat berubah/tidak unik dan barcode atau
kode dapat kosong. Nilai tersebut hanya boleh membantu pencarian kandidat.

### Memakai `sirs.KonversiSatuanItem` untuk semua domain

Ditolak karena model tersebut spesifik medis dan tidak menyediakan kontrak
generik tenant, precision, version, serta pasangan item/UOM lintas domain.

### Menyimpan lokasi sebagai string bebas

Ditolak karena tidak dapat menjamin tenant, hierarki gudang-zone-bin, kapasitas,
atau referential integrity.

## Rollout dan verification gates

1. Jalankan preflight read-only Fase 2 pada salinan/staging dan simpan hasilnya.
2. Tetapkan tenant serta mapping item/lokasi; mapping ambigu tidak boleh lolos.
3. Review migration additive dan rollback sebelum eksekusi DDL.
4. Backfill idempoten dalam batch kecil, disertai checksum dan checkpoint.
5. Jalankan shadow-read/dual-reference dan tolak mismatch.
6. UAT wajib membuktikan collision lintas tipe tidak terjadi, validasi input
   bekerja, dan konversi UOM round-trip sesuai precision.
7. Cutover hanya setelah laporan rekonsiliasi bersih dan feature flag rollback
   tersedia.

