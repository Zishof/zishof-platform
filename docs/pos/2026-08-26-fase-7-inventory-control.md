# Fase 7 — Inventory Control, Karantina, dan FEFO

## Outcome

Fondasi domain Inventory Control sudah tersedia untuk cycle count, koreksi stok berotorisasi, pelepasan karantina, dan perencanaan FEFO. Semua perubahan kuantitas tetap melalui ledger persediaan Fase 3; modul ini tidak membuat sumber saldo kedua.

## Keputusan integrasi

- Cycle count berstatus `DRAFT`/`COUNTING`/`SUBMITTED` tidak boleh mengubah stok. Selisih baru diposting setelah status `APPROVED`.
- Selisih setiap baris memakai kunci stabil `CYCLE_COUNT:{lineId}:ADJUSTMENT`. Retry wajib menjadi replay idempoten.
- Selisih nol tidak membuat movement. Selisih bukan nol wajib memiliki alasan.
- Posting koreksi memakai `InventoryPostingPort`, sehingga saldo dan ledger tetap satu sumber kebenaran.
- Pelepasan karantina adalah transisi status lot melalui `InventoryLotControlPort`, bukan movement kuantitas positif. Ini mencegah saldo ganda atas barang yang sebelumnya sudah diterima.
- Lot kedaluwarsa tidak dapat dilepas dari karantina.
- FEFO hanya memilih saldo tersedia yang positif, tidak dikarantina, dan belum kedaluwarsa pada waktu bisnis.
- Urutan FEFO deterministik: tanggal kedaluwarsa terdekat, lalu `lotId`. Lot tanpa tanggal kedaluwarsa ditempatkan terakhir.

## Alur target

### Cycle count

1. Petugas membuat header dan snapshot kuantitas sistem per lokasi/item/lot.
2. Petugas memasukkan kuantitas fisik dan alasan selisih.
3. Supervisor menyetujui dokumen.
4. Adapter mengunci header dan saldo terkait, lalu memvalidasi ulang status.
5. Seluruh selisih diposting atomik ke ledger sebagai `STOCK_ADJUSTMENT`.
6. Jika satu baris gagal, seluruh transaksi di-rollback; status tidak menjadi `POSTED`.

### Karantina

1. QC atau kontrol persediaan mencatat lot yang dikarantina.
2. Supervisor menyetujui pelepasan dengan alasan dan kuantitas yang sah.
3. Adapter mengunci lot, memastikan belum kedaluwarsa dan kuantitas masih cukup.
4. Status lot diubah dan event audit disimpan dalam transaksi yang sama.
5. Tidak ada movement kuantitas baru karena barang tidak berpindah kepemilikan/lokasi.

### FEFO

1. Adapter membaca kandidat lot berdasarkan tenant, lokasi, item, dan UOM.
2. Kandidat expired, quarantined, atau tanpa saldo dikeluarkan.
3. Planner mengurutkan expiry terdekat dan membagi alokasi sampai permintaan terpenuhi.
4. Kekurangan dikembalikan eksplisit; reservasi dan posting outbound tetap tanggung jawab Fase 8.

## Artefak implementasi

- Domain cycle count: `ais.common.inventory.control.CycleCount` dan `CycleCountLine`.
- Domain karantina: `ais.common.inventory.control.QuarantineRelease`.
- Port status lot: `InventoryLotControlPort` dan `InventoryLotControlResult`.
- Kandidat FEFO: `FefoLotCandidate`.
- Orkestrasi: `InventoryControlService`.
- UAT executable: `InventoryControlServiceUat`.
- Draft DDL: `2026-08-26-fase-7-schema-inventory-control.sql`.

Kode authoritative berada di `C:\opt\AIS\ais\src\main\src` dan dicerminkan ke `C:\opt\AIS\ais\src\main\java`. Hasil kompilasi wajib diarahkan ke `C:\opt\AIS\ais\.codex-build`; dilarang menghasilkan `.class` di direktori source.

## Cakupan UAT kontrak

Eksekusi lokal pada 26 Agustus 2026 memakai `javac -source 1.7 -target 1.7` dengan output terisolasi di `C:\opt\AIS\ais\.codex-build\phase7-control`. Hasilnya: `InventoryControlServiceUat: LULUS`.

- Selisih positif dan negatif diposting; selisih nol dilewati.
- Retry idempotency key yang sama tidak membuat movement kedua.
- Cycle count yang belum disetujui ditolak.
- Selisih tanpa alasan ditolak.
- Pelepasan karantina valid dan replay idempoten berhasil tanpa memanggil posting kuantitas.
- Lot kedaluwarsa ditolak untuk pelepasan.
- FEFO mengecualikan lot expired/quarantined dan mengalokasikan secara deterministik.

## Yang belum diaktifkan

- Draft DDL belum dijalankan pada database mana pun.
- Belum ada adapter Hibernate/JDBC untuk lock, persistensi, atau perubahan status lot.
- Belum ada approval UI, cycle-count scanner, label karantina, atau monitor expiry.
- Belum ada UAT PostgreSQL untuk transaksi atomik, konkurensi, dan rekonsiliasi saldo.
- FEFO belum melakukan reservasi; fungsi saat ini read-only agar tidak bersaing dengan writer Fase 8.

## Gerbang staging

1. Sahkan mapping tenant, gudang/lokasi, item, UOM, dan lot kanonis.
2. Review DDL, backup, rollback, lalu jalankan hanya di staging.
3. Implementasikan adapter dalam satu transaksi database dengan row lock yang terukur.
4. Uji dua koneksi mem-posting idempotency key sama; hanya satu ledger boleh tercipta.
5. Rekonsiliasi saldo sebelum/sesudah adjustment dan buktikan pelepasan karantina tidak menambah kuantitas.
6. Uji FEFO pada lot tanpa expiry, expiry sama, expired, quarantined, dan shortage.
7. Aktifkan bertahap melalui feature flag setelah sign-off supervisor gudang dan akuntansi.

## Rollback

Sebelum adapter runtime aktif, rollback cukup menonaktifkan feature flag dan menghapus draft yang belum dipakai. Movement yang sudah terposting tidak boleh dihapus; koreksi dilakukan dengan reversal ledger berotorisasi. Event status lot tetap disimpan sebagai audit trail.

## Fase berikutnya

Fase 8 adalah Outbound & Distribusi: reservasi, picking, packing, delivery order, shipment, handover custody, proof of delivery, dan penerimaan outlet tanpa menduplikasi BAST vendor.
