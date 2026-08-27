# Implementasi Fase 4: Fondasi Replenishment Outlet

Tanggal: 26 Agustus 2026

## Hasil fase

Fondasi domain replenishment outlet telah dibuat sebagai planner **read-only**. Planner menerima permintaan stok internal outlet, membaca ketersediaan gudang melalui port, lalu memisahkan kuantitas menjadi:

- jumlah yang dapat dipenuhi dari gudang; dan
- kekurangan yang perlu diteruskan ke proses procurement.

Implementasi ini sengaja belum membuat PR, belum mereservasi stok, belum menulis ledger, dan belum mengubah transaksi existing. Batas tersebut mencegah stock request internal disamakan dengan PR vendor serta mencegah perubahan parsial sebelum persistence dan workflow approval tersedia.

## Batas domain

`OutletReplenishmentRequest` adalah permintaan internal dari outlet ke gudang utama. Dokumen ini bukan `PermintaanPengadaanMasterAsset` dan bukan purchase requisition vendor.

Alur targetnya:

1. outlet mengirim stock request;
2. planner memeriksa stok gudang;
3. stok tersedia dialokasikan pada rencana pemenuhan;
4. kekurangan dicatat sebagai kebutuhan procurement;
5. pada fase integrasi berikutnya, kekurangan yang disetujui dapat menghasilkan PR melalui adapter procurement, bukan langsung dari planner.

## Kode yang ditambahkan

Sumber kanonis:

- `ais.common.inventory.replenishment.ReplenishmentAvailabilityPort`
- `ais.common.inventory.replenishment.OutletReplenishmentLine`
- `ais.common.inventory.replenishment.OutletReplenishmentRequest`
- `ais.common.inventory.replenishment.OutletReplenishmentPlanLine`
- `ais.common.inventory.replenishment.OutletReplenishmentPlan`
- `ais.common.inventory.replenishment.OutletReplenishmentPlanner`

Lokasi kanonis: `C:\opt\AIS\ais\src\main\src\ais\common\inventory\replenishment`.

Mirror source pada `C:\opt\AIS\ais\src\main\java\ais\common\inventory\replenishment` disamakan byte-for-byte untuk mengikuti struktur build existing.

## Status rencana

- `READY_FROM_WAREHOUSE`: seluruh permintaan dapat dipenuhi gudang.
- `PARTIAL_PROCUREMENT_REQUIRED`: sebagian dapat dipenuhi gudang dan sisanya memerlukan procurement.
- `PROCUREMENT_REQUIRED`: gudang tidak memiliki stok yang dapat dialokasikan.
- `REJECTED`: request melanggar kontrak input.
- `FAILED`: pembacaan ketersediaan gagal; tidak ada hasil parsial yang dianggap berhasil.

## Validasi kontrak

Request ditolak sebelum akses stok apabila:

- tenant, lokasi sumber, atau lokasi tujuan tidak valid;
- lokasi sumber sama dengan lokasi tujuan;
- nomor request atau idempotency key kosong;
- waktu atau baris request tidak tersedia;
- nomor baris duplikat; atau
- kombinasi item dan UOM muncul lebih dari satu kali.

DTO melakukan defensive copy pada `Date` dan koleksi agar hasil perencanaan tidak berubah setelah dibuat.

## UAT yang dijalankan

Kompilasi dilakukan dengan `javac -source 1.7 -target 1.7`. Seluruh gerbang kontrak berikut lulus:

- `InventoryMovementContractUat`: LULUS.
- `InventoryMasterReferenceContractUat`: LULUS.
- `InventoryLedgerDomainContractUat`: LULUS.
- `InventoryShadowWriteAndReconciliationUat`: LULUS.
- `OutletReplenishmentPlannerUat`: LULUS.

Skenario Fase 4 yang dibuktikan:

- stok penuh: seluruh kuantitas dialokasikan dari gudang;
- stok parsial: alokasi gudang dan shortage procurement dihitung terpisah;
- stok habis: seluruh kuantitas menjadi kebutuhan procurement;
- request invalid: availability port tidak dipanggil;
- kegagalan pembaca stok: status `FAILED` tanpa perubahan parsial; dan
- mutasi objek input setelah planning tidak mengubah hasil.

Audit source juga memastikan tidak ada lambda, Stream API, try-with-resources, atau sintaks Java 8+ pada implementasi fase ini. Enam file kanonis dan mirror memiliki SHA-256 yang sama.

## Belum termasuk / gerbang fase berikutnya

Fondasi ini belum siap cutover produksi. Pekerjaan berikutnya:

1. tentukan tabel header/detail stock request internal dan lifecycle approval;
2. buat adapter ketersediaan dari balance/ledger baru setelah Fase 3 lolos UAT database;
3. buat reservasi idempoten saat request disetujui, bukan saat draft dibuat;
4. buat adapter shortage-to-PR yang mempertahankan existing PR/PO/BAST sebagai kanonis;
5. tambahkan audit actor, tenant, lokasi, alasan, dan idempotency key pada persistence;
6. tambahkan role action dan UI setelah route serta rollback migration tersedia; dan
7. jalankan UAT database konkurensi, retry, partial fulfillment, cancel, serta rollback sebelum pilot.

Tidak ada DDL/DML produksi, commit, push, build release, atau publikasi GitHub pada fase ini.
