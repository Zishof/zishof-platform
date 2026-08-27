# Fase 5: konsolidasi replenishment ke procurement existing

## Hasil fase

Fase ini menambahkan batas integrasi yang mengubah kekurangan stok hasil
perencanaan replenishment outlet menjadi draft PR vendor. Implementasi tidak
membuat keluarga tabel PR baru. Penyimpanan produksi tetap harus diarahkan ke
model existing `PermintaanPengadaanMasterAsset` dan
`PermintaanPengadaanMasterAssetDetail` melalui implementasi
`ProcurementRequisitionPort`.

Komponen kanonis berada di:

- `src/main/src/ais/common/inventory/procurement`
- mirror kompatibilitas: `src/main/java/ais/common/inventory/procurement`

## Kontrak dan perilaku

- Hanya baris dengan shortage procurement yang diteruskan ke draft PR.
- Baris yang dapat dipenuhi gudang tidak ikut dibuatkan PR.
- Jika seluruh stok cukup, hasilnya `NOT_REQUIRED` dan port tidak dipanggil.
- Plan atau request yang tidak valid menghasilkan `REJECTED` tanpa write.
- Kunci idempotensi replenishment diberi suffix `:SHORTAGE-PR` sehingga retry
  wajib menemukan PR yang sama, bukan membuat dokumen kedua.
- Adapter yang mengembalikan `null` atau melempar runtime exception menghasilkan
  `FAILED`; draft tetap dibawa pada hasil untuk kebutuhan audit dan retry.
- DTO menyimpan salinan defensif tanggal dan daftar baris agar caller tidak dapat
  mengubah draft setelah validasi.

Status hasil yang tersedia adalah `CREATED`, `ALREADY_EXISTS`, `NOT_REQUIRED`,
`REJECTED`, dan `FAILED`.

## Batas integrasi dengan tabel existing

Implementasi konkret `ProcurementRequisitionPort` kini tersedia sebagai
`HibernateProcurementRequisitionPort`. Kontrak implementasinya:

1. melakukan lookup kunci idempotensi sebelum insert;
2. memetakan tenant, gudang sumber, outlet tujuan, item, dan UOM menggunakan
   bridge identitas Fase 2;
3. menulis header/detail ke PR existing dalam satu transaksi database;
4. mengembalikan `ALREADY_EXISTS` untuk retry dengan kunci yang sama;
5. tidak menciptakan tabel PR termin/nontermin baru; termin tetap merupakan
   schedule pembayaran pada PO/tagihan;
6. tidak menutup `currentSession()` secara manual; jika menggunakan
   `openSession()` atau `currentNativeSession()`, wajib
   `clear/disconnect/close` dalam `finally`.

## UAT yang dijalankan

UAT mandiri:

`src/test/java/ais/common/inventory/procurement/ReplenishmentShortageToProcurementUat.java`

Kompilasi dilakukan dengan Java 1.7 ke direktori terpisah:

`C:\opt\AIS\ais\.codex-build\phase5-20260826`

Hasil verifikasi:

- `InventoryMovementContractUat`: LULUS
- `InventoryMasterReferenceContractUat`: LULUS
- `InventoryLedgerDomainContractUat`: LULUS
- `InventoryShadowWriteAndReconciliationUat`: LULUS
- `OutletReplenishmentPlannerUat`: LULUS
- `ReplenishmentShortageToProcurementUat`: LULUS

Peringatan `bootstrap class path not set in conjunction with -source 1.7`
berasal dari compiler JDK 8; source dan target tetap ditetapkan ke 1.7.

## Yang belum dilakukan

- Adapter write ke model PR existing sudah tersedia, tetapi belum diaktifkan dan
  belum dijalankan pada database staging/produksi.
- Draft migration bridge idempotensi sudah tersedia, tetapi belum direview atau
  dieksekusi pada database.
- Resolver konkret tenant, outlet, item, dan UOM belum dihubungkan ke runtime.
- Belum ada UAT transaksi database dan concurrency untuk adapter PR.
- Belum ada approval workflow, pembuatan PO, invoice vendor, atau posting jurnal.
- Belum boleh mengaktifkan integrasi ini pada produksi.

## Gerbang fase berikutnya

Sebelum menghubungkan adapter ke runtime, review dan jalankan draft bridge pada
staging, implementasikan resolver berdasarkan mapping yang disetujui, lalu
lakukan UAT dua koneksi untuk membuktikan retry/concurrency hanya membuat satu
PR. Jika gerbang ini lulus, pekerjaan dapat dilanjutkan ke WMS inbound
(penerimaan vendor, QC, putaway, lot, dan lokasi).

## Kebersihan source tree

Semua kompilasi wajib mengikuti
`2026-08-26-pencegahan-class-di-source-tree.md`. File `.class` tidak boleh
dihasilkan berdampingan dengan `.java` dan tidak boleh masuk SVN/Git.
