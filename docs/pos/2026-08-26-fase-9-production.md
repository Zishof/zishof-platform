# Fase 9 — Fondasi Produksi

## Outcome

Fase ini menyediakan kontrak domain produksi yang memakai ledger persediaan kanonis. Implementasi mencakup BOM/resep berversi, work order, issue dan return bahan, penerimaan hasil produksi, waste/scrap, perhitungan biaya, serta traceability lot. Seluruh perubahan masih bersifat additive dan belum mengaktifkan writer pada database produksi.

## Batas proses

Alur yang dicakup:

1. BOM berstatus `DRAFT`, `ACTIVE`, atau `RETIRED` mendefinisikan produk keluaran dan kebutuhan komponen.
2. Work order bergerak `DRAFT -> RELEASED -> IN_PROGRESS -> COMPLETED` atau `CANCELLED`.
3. Bahan yang benar-benar dipakai dicatat sebagai movement negatif `PRODUCTION_MATERIAL_ISSUE`.
4. Bahan yang dikembalikan dicatat sebagai movement positif `PRODUCTION_MATERIAL_RETURN`.
5. Hasil produksi yang lolos dicatat sebagai movement positif `PRODUCTION_OUTPUT_RECEIPT` dan wajib membawa lot.
6. Waste yang mengurangi stok dicatat sebagai movement negatif `PRODUCTION_WASTE`; waste nonstok tetap dicatat pada workflow produksi.
7. Genealogi menghubungkan lot bahan dengan lot hasil sehingga penelusuran maju dan mundur dapat dilakukan.

Tabel legacy `koperasi.produksi_kantin` dan `koperasi.pemakaian_bahan_baku` dipertahankan sebagai sumber kompatibilitas. Keduanya tidak dijadikan sumber kebenaran baru dan tidak dihapus pada fase ini.

## Kontrak idempotensi

Kunci operasi bersifat stabil dan dibentuk dari work order, kelompok operasi, referensi, dan aksi. Contoh:

- `PRODUCTION:<order>:MATERIAL:<line>:ISSUE`
- `PRODUCTION:<order>:MATERIAL:<line>:RETURN`
- `PRODUCTION:<order>:OUTPUT:<line>:RECEIVE`
- `PRODUCTION:<order>:WASTE:<line>:RECORD`
- `PRODUCTION:<order>:WORKFLOW:<reference>:RELEASE|START|COMPLETE`

Retry dengan kunci dan payload sama harus menghasilkan `ALREADY_APPLIED`. Kunci sama dengan payload berbeda harus ditolak sebagai konflik, bukan diposting ulang.

## Aturan kuantitas dan biaya

- Kebutuhan BOM diskalakan terhadap kuantitas dasar dan memperhitungkan persentase kehilangan yang diharapkan.
- Quantity input, output, dan waste harus positif pada kontrak domain; tanda ledger ditentukan oleh jenis kejadian.
- Biaya bahan berasal dari `quantity x unitCost` per baris.
- Total biaya produksi adalah bahan + tenaga kerja + overhead.
- Biaya satuan hanya dapat dihitung jika output diterima lebih besar dari nol.
- UOM dan item menggunakan ID kanonis dari Fase 2. Konversi UOM tidak boleh ditebak dari nama atau kebetulan ID legacy.

## Artefak implementasi

Kode utama berada di `src/main/src/ais/common/inventory/production` dan mirror kompatibilitas berada di `src/main/java/ais/common/inventory/production`.

- `BillOfMaterial` dan `BillOfMaterialLine`
- `ProductionWorkOrder`
- `ProductionMaterialLine`, `ProductionOutputLine`, dan `ProductionWasteLine`
- `ProductionWorkflowCommand`, `ProductionWorkflowResult`, dan `ProductionWorkflowPort`
- `ProductionOperationResult` dan `ProductionCostSummary`
- `ProductionService`

Draft skema tersedia pada `2026-08-26-fase-9-schema-production.sql`. Skrip tersebut belum dijalankan.

## Batas transaksi adapter

`ProductionService` mengoordinasikan port workflow dan `InventoryPostingPort`, tetapi kontrak Java ini sendiri tidak membuka transaksi database. Adapter runtime wajib menyediakan satu Unit of Work yang mencakup:

1. perubahan status/workflow produksi;
2. insert dokumen dan baris produksi;
3. posting seluruh movement ledger;
4. penyimpanan genealogi lot; dan
5. audit/idempotency record.

Semua langkah harus commit atau rollback bersama. Memanggil beberapa posting dalam transaksi terpisah dapat menghasilkan issue bahan parsial dan tidak boleh diaktifkan pada produksi. Locking work order dan saldo mengikuti urutan deterministik untuk mencegah deadlock.

## Cakupan UAT kontrak

`ProductionServiceUat` memverifikasi:

- scaling BOM dan expected loss;
- penolakan null dan kuantitas tidak valid;
- issue bahan negatif dan retry idempoten;
- return bahan positif;
- penerimaan output positif, wajib lot, dan penolakan output yang tidak sesuai BOM;
- waste stok dan nonstok;
- kalkulasi biaya bahan, tenaga kerja, overhead, total, dan biaya satuan;
- transisi release, start, dan complete.

Kompilasi harus menggunakan `javac -source 1.7 -target 1.7`. Output wajib diarahkan ke direktori build terisolasi; jangan pernah membuat `.class` di direktori yang sama dengan `.java`.

## Yang belum diaktifkan

- DDL belum dijalankan pada database mana pun.
- Belum ada adapter Hibernate/JDBC untuk tabel produksi baru.
- Belum ada bridge runtime dari `ProduksiKantin`/`PemakaianBahanBaku` ke ledger baru.
- Belum ada UI Desktop, Android, JSP, atau ZK untuk workflow produksi baru.
- Belum ada posting jurnal akuntansi produksi.

## Gerbang staging

Aktivasi hanya boleh dilanjutkan setelah:

1. mapping tenant, lokasi, item, UOM, dan lot disetujui;
2. DDL direview dan dijalankan di database UAT khusus;
3. adapter Unit of Work lulus pengujian rollback dan concurrency;
4. retry idempoten tidak menggandakan movement maupun genealogi;
5. rekonsiliasi bahan, WIP, output, waste, dan biaya bernilai nol mismatch; dan
6. feature flag writer tetap default `OFF` sampai sign-off.

## Rollback

Karena schema bersifat additive, rollback tahap awal dilakukan dengan menonaktifkan feature flag writer dan tetap memakai alur legacy. Penghapusan tabel tidak dilakukan sebagai rollback otomatis. Data staging baru dapat diarsipkan setelah rekonsiliasi dan persetujuan eksplisit.

## Fase berikutnya

Fase 10 membangun AP dan akuntansi: invoice vendor kanonis, three-way match PR/PO/receipt/invoice, pembayaran, serta posting jurnal yang tidak lagi menyalahgunakan tabel saldo awal.
