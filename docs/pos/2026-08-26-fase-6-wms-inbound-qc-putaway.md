# Fase 6 — WMS Inbound, QC, dan Putaway

## Outcome

Fondasi domain inbound sudah tersedia untuk menghubungkan PO/BAST existing dengan lot, QC, lokasi gudang, dan ledger persediaan. Barang yang baru diterima belum dianggap stok *available*. Perubahan saldo hanya boleh terjadi setelah QC menerima kuantitas dan putaway ke lokasi tujuan selesai.

Dokumen ini adalah Fase Eksekusi 6. Pada blueprint domain terdahulu pekerjaan yang sama kadang disebut Fase 7 karena fase menu dihitung terpisah.

## Keputusan integrasi

- `PenerimaanPengadaanMasterAsset` dan detailnya tetap menjadi BAST formal. Tidak dibuat BAST vendor kedua.
- Goods receipt WMS menyimpan konteks operasional penerimaan, hasil QC, lot/kedaluwarsa, dan lokasi receiving.
- BAST dan QC tidak langsung menambah saldo *available*. Posting dilakukan sekali saat putaway selesai.
- Setiap detail putaway memakai kunci `PUTAWAY:{putawayDetailId}:MOVE`. Retry dengan kunci sama harus menghasilkan replay idempoten, bukan saldo ganda.
- Kuantitas diterima wajib sama dengan jumlah diterima QC: accepted + rejected + quarantined.
- Hanya kuantitas accepted yang dapat dipindahkan ke lokasi stok. Accepted wajib mempunyai `lotId` konkret.
- Jumlah detail putaway per baris penerimaan wajib persis sama dengan kuantitas accepted.
- Status penerimaan yang boleh diposting hanya `ACCEPTED`, `PARTIALLY_ACCEPTED`, atau replay `POSTED`.

## Alur target

1. PO/BAST menjadi referensi inbound shipment dan goods receipt.
2. Petugas mencatat kuantitas fisik di lokasi receiving.
3. QC membagi kuantitas menjadi accepted, rejected, dan quarantined serta menetapkan lot/kedaluwarsa.
4. Sistem membuat tugas putaway untuk kuantitas accepted.
5. Setelah setiap tugas selesai, layanan membuat `InventoryMovementCommand` bertipe `PUTAWAY` dan event `INBOUND_AVAILABLE`.
6. `InventoryPostingPort` mem-posting ledger dan saldo secara atomik/idempoten.
7. Rejected dan quarantined tetap terpisah serta tidak masuk saldo jual.

## Artefak implementasi

- Domain dan validasi: `ais.common.inventory.inbound.GoodsReceipt` dan `GoodsReceiptLine`.
- Instruksi putaway: `ais.common.inventory.inbound.PutawayInstruction`.
- Orkestrasi posting: `ais.common.inventory.inbound.WarehouseInboundService`.
- Hasil proses: `ais.common.inventory.inbound.WarehouseInboundResult`.
- UAT executable: `WarehouseInboundServiceUat`.
- Draft DDL: `2026-08-26-fase-6-schema-wms-inbound.sql`.

Kode authoritative berada di `C:\opt\AIS\ais\src\main\src` dan dicerminkan ke `C:\opt\AIS\ais\src\main\java`. Hasil kompilasi wajib diarahkan ke `C:\opt\AIS\ais\.codex-build` agar tidak menghasilkan `.class` di samping `.java`.

## Cakupan UAT kontrak

Eksekusi lokal pada 26 Agustus 2026 menggunakan `javac -source 1.7 -target 1.7` dan output terisolasi di `C:\opt\AIS\ais\.codex-build\phase6-inbound` menghasilkan `WarehouseInboundServiceUat: LULUS`. Tidak ada berkas `.class` yang dibuat di direktori source.

- Putaway valid mem-posting kuantitas accepted dengan lokasi, item, UOM, lot, dan waktu bisnis yang benar.
- Retry idempotency key yang sama tidak menambah mutasi kedua.
- Receipt yang masih `IN_QC` ditolak.
- Detail putaway yang belum selesai ditolak.
- Total putaway yang berbeda dari accepted ditolak.
- Accepted tanpa `lotId` ditolak.
- Skenario partial hanya mem-posting accepted; rejected dan quarantined tidak ikut masuk saldo.
- Nilai tanggal dan daftar domain menggunakan defensive copy.

## Yang belum diaktifkan

- Draft DDL belum dijalankan pada database mana pun.
- Belum ada adapter persistence WMS atau resolver konkret ke tabel PO/BAST/item/UOM/lokasi.
- Belum ada UI receiving, QC, putaway, approval, atau migrasi data lama.
- Belum ada UAT konkurensi PostgreSQL dan reconciliation terhadap stok production.

## Gerbang staging

1. Sahkan mapping ID kanonis Fase 2 dan referensi PO/BAST Fase 5.
2. Review DDL, backup, rollback, lalu jalankan hanya di staging.
3. Buat adapter transaksi database dan uji dua koneksi dengan idempotency key sama.
4. Buktikan BAST tidak lagi menjadi writer stok kedua.
5. Rekonsiliasi receipt, QC, putaway, ledger, dan saldo hingga nol mismatch.
6. Aktifkan melalui feature flag pada pilot warehouse setelah sign-off.

## Rollback

Sebelum cutover, implementasi hanya kontrak dan draft skema sehingga rollback cukup dengan menonaktifkan adapter/feature flag. Setelah DDL staging, rollback harus menghapus tabel dalam urutan detail ke header dan hanya dilakukan bila tidak ada ledger yang sudah diposting. Ledger yang sudah terposting harus dibalik dengan movement reversal, bukan dihapus.

## Fase berikutnya

Fase 7 adalah Inventory Control: cycle count, adjustment approval, quarantine release, monitoring expiry/FEFO, dan seluruh koreksi melalui ledger yang sama.
