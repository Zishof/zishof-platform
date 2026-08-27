# Fase 5: adapter persistensi PR existing

Tanggal: 26 Agustus 2026

## Hasil

Adapter Hibernate untuk meneruskan shortage replenishment ke dokumen PR existing
telah dibuat. Implementasi memakai `PermintaanPengadaanMasterAsset` dan
`PermintaanPengadaanMasterAssetDetail`; tidak membuat keluarga tabel PR baru.
Metadata integrasi dan kunci idempotensi disimpan pada tabel bridge terpisah agar
semantik entity legacy, termasuk `kodeUnik`, tidak berubah.

Kode kanonis dan mirror kompatibilitas berada di:

- `src/main/src/ais/common/inventory/procurement`
- `src/main/java/ais/common/inventory/procurement`

Draft migration berada di:

- `src/main/docs/sql/2026-08-26-procurement-requisition-bridge.sql`

## Komponen

- `ProcurementRequisitionLegacyReferenceResolver` memisahkan resolusi identitas
  domain baru dari entity legacy.
- `HibernateProcurementRequisitionPort` melakukan lookup idempotensi, validasi
  referensi, insert header/detail PR existing, dan pencatatan bridge dalam satu
  transaksi.
- `procurement_document_extension` menyimpan hubungan dokumen sumber, tenant,
  lokasi, PR legacy, dan kunci idempotensi.
- `procurement_item_reference` menyimpan hubungan baris canonical item/UOM/qty
  dengan detail PR legacy.

## Matriks pemetaan

| Data kanonis | Tujuan legacy/bridge | Cara memperoleh |
|---|---|---|
| Pengguna peminta | `Tbmuser` pada header PR | `resolveRequesterUserId` |
| Outlet tujuan | `Toko` pada header PR | `resolveTargetTokoId` |
| Item shortage | `MasterAsset` pada detail PR | `resolveMasterAssetId` |
| Tenant dan lokasi | tabel bridge | nilai draft replenishment |
| Item dan UOM kanonis | tabel bridge detail | nilai baris draft |
| Kunci retry | unique constraint tabel bridge | idempotency key draft |

Resolver wajib menolak mapping yang ambigu. ID numerik yang kebetulan sama pada
`Produk`, `MasterAsset`, atau item SIRS tidak boleh dianggap identitas yang sama.

## Transaksi dan idempotensi

1. Adapter memvalidasi draft sebelum membuka session.
2. Kunci idempotensi dicari pada bridge sebelum insert.
3. Header PR, detail PR, extension dokumen, dan reference item ditulis dalam satu
   transaksi Hibernate.
4. Retry dengan kunci yang sudah ada mengembalikan `ALREADY_EXISTS`.
5. Race unique constraint ditangani dengan rollback, session pertama ditutup,
   lalu hasil existing dibaca ulang.
6. `kodeUnik` entity legacy tidak dipakai untuk idempotensi karena getter existing
   menghitung ulang nilainya dari kode PR dan disposisi.

## Lifecycle session

Adapter memakai `openSession()`. Session selalu ditutup melalui
`HibernateUtil.closeSessionQuietly(session)` pada `finally`, yang mencakup
clear/disconnect/close. Tidak ada `currentSession()` yang ditutup manual.

## UAT

Kompilasi dilakukan dengan `-source 7 -target 7` dan output hanya ke
`C:\opt\AIS\ais\.codex-build`; tidak ada `.class` yang dihasilkan di source tree.

Hasil:

- `ReplenishmentShortageToProcurementUat`: **LULUS**.
- `HibernateProcurementRequisitionPortUat`: **LULUS**.
- Source kanonis dan mirror adapter: **identik SHA-256**.

UAT saat ini membuktikan validasi, pembentukan identitas PR deterministik,
pemetaan hasil, dan kontrak idempotensi tanpa database. UAT transaksi database
dan dua koneksi bersamaan belum dijalankan.

## Batas aktivasi produksi

Implementasi belum boleh diaktifkan pada produksi sebelum seluruh gerbang berikut
lulus:

1. review dan eksekusi draft DDL bridge pada database staging;
2. implementasi resolver konkret berdasarkan mapping tenant/lokasi/item/UOM yang
   telah disetujui;
3. UAT transaksi database nyata untuk commit dan rollback;
4. UAT concurrency dua koneksi dengan idempotency key sama, membuktikan hanya
   satu PR terbentuk;
5. verifikasi workflow approval PR existing tetap berjalan;
6. rekonsiliasi dokumen sumber, PR header/detail, dan bridge tanpa orphan.

## Status repository

Perubahan masih lokal. Pada fase ini tidak dilakukan commit SVN, commit/push Git,
build release, deployment, ataupun publikasi GitHub.
