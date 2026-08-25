# Gap analysis tabel existing dan target terpadu eBisnis

Tanggal: 25 Agustus 2026  
Status: rancangan arsitektur data; belum merupakan DDL produksi  
Blueprint acuan: [Audit redundansi dan blueprint menu terpadu eBisnis](2026-08-25-audit-redundansi-dan-blueprint-menu-terpadu.md)

## 1. Tujuan dan batas analisis

Dokumen ini menggantikan pemetaan tabel yang hanya berfokus pada Pergudangan. Ruang
lingkupnya mengikuti batas domain pada blueprint menu terbaru: Master Data,
Perencanaan, Pengadaan, Pergudangan, Distribusi, Produksi, Keuangan, Akuntansi,
Laporan, dan Sistem.

Tujuan utamanya adalah menentukan untuk setiap kebutuhan apakah tabel existing:

1. dipakai apa adanya;
2. diubah secara kompatibel dengan `ALTER TABLE`;
3. dipertahankan tetapi diberi tabel ekstensi/bridge;
4. dimigrasikan ke tabel baru;
5. hanya menjadi adapter/view selama masa transisi; atau
6. dihentikan sebagai sumber tulis setelah cutover.

Analisis bersumber dari model Java dan alur existing, khususnya package
`ais.database.model.asset`, `ais.database.model.inventory`,
`ais.database.model.koperasi`, `ais.database.model.akunting`, action Pengadaan,
action Keuangan/Akuntansi, katalog menu POS, serta dokumen audit sebelumnya.

Dokumen ini **tidak** mengizinkan pembuatan tabel atau perubahan kolom langsung di
produksi. Nama tabel baru di bawah adalah nama logis yang harus dikonfirmasi terhadap
konvensi schema tenant sebelum migration SQL dibuat.

## 2. Ringkasan keputusan arsitektur

### 2.1 Keputusan utama

1. Tabel PR, PO, dan BAST existing tetap dipakai sebagai canonical procurement
   document pada fase awal. Workflow, nomor dokumen, persetujuan, termin, dan relasi
   yang sudah berjalan tidak boleh dibuang.
2. Detail PR/PO/BAST existing berorientasi `MasterAsset`. Dukungan barang dagang,
   bahan baku, barang setengah jadi, barang jadi, jasa, dan biaya harus ditambahkan
   melalui **item reference/extension**, bukan dengan menyamarkan `Produk` sebagai
   `MasterAsset`.
3. `asset.saldo_awal_master_asset` tidak layak menjadi canonical tagihan vendor
   jangka panjang. Nama dan tanggung jawabnya bertentangan dengan konsep Account
   Payable. Dibuat `ap_invoice` dan `ap_invoice_line`, sedangkan tabel lama menjadi
   sumber migrasi dan adapter kompatibilitas.
4. `akunting.proses_transfer` dan `akunting.daftar_pengajuan_transfer` tetap menjadi
   workflow pembayaran/transfer. Relasi pembayaran ke invoice dibuat melalui tabel
   alokasi baru agar tidak menambah deretan foreign key nullable untuk setiap jenis
   dokumen.
5. Semua perubahan stok baru harus menghasilkan tepat satu event pada ledger
   `inventory_movement`. Kolom stok pada produk/batch hanya menjadi proyeksi/cache,
   bukan sumber kebenaran kedua.
6. Permintaan stok outlet, PR vendor, pesanan pelanggan, dan production order adalah
   aggregate berbeda. Nama mirip tidak menjadi alasan memakai satu tabel.
7. BAST vendor berbeda dari penerimaan transfer outlet/POD. Keduanya tidak boleh
   berbagi nomor dokumen atau status lifecycle.
8. `asset.pengiriman_gudang` dan `koperasi.mutasi_stok_toko` dipertahankan sebagai
   adapter legacy. Proses baru menggunakan aggregate transfer, DO, shipment, dan
   receipt yang terpisah.
9. Laporan dan dashboard tidak memiliki tabel transaksi sendiri. Gunakan view,
   materialized view, atau read model yang dapat dibangun ulang.
10. Tidak dibuat tabel harian seperti `transaksi_DD_MM_YYYY`. Gunakan tabel stabil,
    index yang benar, dan partition bulanan hanya apabila hasil pengukuran volume
    membuktikan perlu.

### 2.2 Legenda keputusan

| Kode | Arti |
|---|---|
| `REUSE` | Dipakai sebagai canonical source tanpa perubahan struktur besar. |
| `ALTER` | Ditambah constraint/index/kolom yang kompatibel. |
| `EXTEND` | Tabel existing tetap, data baru disimpan pada extension satu-ke-satu/bridge. |
| `NEW` | Aggregate baru karena lifecycle dan owner domain berbeda. |
| `ADAPTER` | Masih dibaca/ditulis sementara untuk kompatibilitas, bukan target akhir. |
| `PROJECT` | Cache/read model yang dapat dibangun ulang dari sumber canonical. |
| `RETIRE-WRITE` | Data dipertahankan, tetapi penulisan baru dihentikan setelah cutover. |

## 3. Peta data existing yang relevan

### 3.1 Pengadaan dan tagihan

| Tabel/model existing | Fungsi aktual | Kekuatan | Gap utama |
|---|---|---|---|
| `asset.permintaan_pengadaan_master_asset` | Header PR dan workflow persetujuan | Nomor, pemohon, persetujuan, unit kerja, budget flag telah matang | Belum mempunyai demand source, gudang tujuan, idempotency, dan status lintas domain yang eksplisit |
| `asset.permintaan_pengadaan_master_asset_detail` | Rincian PR berbasis `MasterAsset` | Relasi jumlah, harga, parent, PO, uang muka telah ada | Tidak dapat merepresentasikan `Produk`, jasa, UOM snapshot, atau partial allocation secara aman |
| `asset.pemesanan_pengadaan_master_asset` | Header PO/perjanjian; mempunyai termin/nontermin | Vendor, nilai, pajak/diskon, pembayaran, PO induk, dan status existing | Tujuan penerimaan, shipment vendor, currency/rate snapshot, idempotency, dan schedule terstruktur belum lengkap |
| `asset.pemesanan_pengadaan_master_asset_detail` | Rincian PO berbasis `MasterAsset` | Relasi PR/BAST dan komponen nilai tersedia | Gap tipe item dan UOM sama dengan detail PR; toleransi penerimaan belum eksplisit |
| `asset.penerimaan_pengadaan_master_asset` | Header BAST/penerimaan vendor | Terhubung ke PO, vendor, tagihan, termin, kurir, posting | BAST administratif bercampur dengan kebutuhan receiving fisik, QC, lot, dan putaway |
| `asset.penerimaan_pengadaan_master_asset_detail` | Rincian BAST | Qty, kondisi, harga, pajak, relasi PR/PO tersedia | Tidak memiliki accepted/rejected/damaged qty terstruktur, lokasi receiving, batch, serial, QC result |
| `asset.saldo_awal_master_asset` | Saat ini juga dipakai sebagai terima tagihan vendor | Sudah terkait penyedia, BAST, nilai, lunas, transfer, pajak, termin | Nama dan owner domain salah; sulit untuk 3-way match, credit note, dispute, dan invoice allocation |
| `asset.saldo_awal_master_asset_detail` | Rincian tagihan/saldo awal | Memiliki nilai/qty dan relasi BAST | Tidak cocok menjadi canonical AP invoice line |
| `koperasi.pengadaan_produk` | Pembelian langsung/kulakan produk | Alur sederhana produk-toko-supplier-faktur | Belum punya document header kuat, idempotency, status approval, receipt/ledger/posting link |
| `koperasi.pengadaan_faktur` | Pengelompokan faktur kulakan | Menjembatani transaksi pembelian produk | Belum menggantikan PO/BAST enterprise dan tidak boleh dipaksa demikian |
| `koperasi.retur_pembelian` | Retur pembelian ke vendor | Sudah sesuai lawan transaksi | Perlu reference ke receipt/lot/ledger reversal dan reason code canonical |

### 3.2 Produk, gudang, batch, dan stok

| Tabel/model existing | Fungsi aktual | Keputusan awal | Gap utama |
|---|---|---|---|
| `koperasi.produk` | Master produk per toko, harga, stok, supplier, UOM, batch, minimum stok | `REUSE + ALTER/EXTEND` | `stok` mutable menjadi sumber ganda; identitas produk lintas toko dan UOM conversion belum tegas |
| `koperasi.toko` | Outlet/toko, termasuk `toko_demo` dan flag gudang pemasok | `REUSE` sebagai lokasi bisnis | Toko tidak sama dengan gudang/zona/bin; perlu relasi eksplisit |
| `sirs.gudang` | Master gudang existing | `REUSE/EXTEND` setelah audit kolom | Belum cukup untuk zona, bin, capability, dan tenant ownership WMS |
| `asset.lokasi` | Master lokasi umum/aset | `REUSE` untuk lokasi organisasi; jangan otomatis dianggap bin | Semantik terlalu luas untuk location inventory yang terkontrol |
| `koperasi.produk_batch` | Batch per produk/toko, tanggal produksi/kedaluwarsa, stok/harga | `ADAPTER/PROJECT` | Stock batch mutable, status belum memakai state machine QC/karantina, lokasi bin belum ada |
| `koperasi.mutasi_produk_batch` | Mutasi masuk/keluar/saldo per batch | `ADAPTER`, lalu backfill ke ledger canonical | Saldo tersimpan per baris berisiko drift; reference/idempotency/correlation terbatas |
| `koperasi.mutasi_stok_toko` | Mutasi produk antar toko | `ADAPTER/RETIRE-WRITE` | Menggabungkan request, shipment, receipt, dan stock move; tidak mendukung partial shipment |
| `koperasi.stok_opname` | Hasil opname per produk/toko | `ADAPTER` | Tidak cukup untuk session, lokasi, recount, approval, dan adjustment terpisah |
| `koperasi.sesi_stok_opname` | Header sesi opname | `REUSE/EXTEND` | Detail count, freeze/snapshot, recount, dan posting adjustment belum canonical |
| `koperasi.ambang_stok_gudang` | Minimum stok produk-gudang | `REUSE/EXTEND` | Min saja; belum ada max, safety stock, lead time, pack rounding, source priority |
| `asset.pengiriman_gudang` | Pengiriman asal-tujuan berbasis lokasi | `ADAPTER` | Header terlalu sederhana untuk DO, FO, shipment leg, tracking, POD, dan klaim |
| `asset.pengiriman_gudang_detail` | Qty kirim/terima/rusak dan harga | `ADAPTER` | Tidak punya allocation/pick/pack/package/lot/serial dan reason detail |

### 3.3 Keuangan dan Akuntansi

| Tabel/model existing | Fungsi aktual | Keputusan awal | Gap utama |
|---|---|---|---|
| `akunting.proses_transfer` | Batch/proses pembayaran dan approval/realisasi | `REUSE` | Perlu idempotency, payment execution reference, dan reconciliation status |
| `akunting.daftar_pengajuan_transfer` | Daftar pengajuan/alokasi sumber pembayaran | `REUSE + EXTEND` | Banyak sumber dokumen berpotensi menjadi banyak FK nullable; perlu allocation generik |
| `akunting.transaksi`, `grup_transaksi`, `jenis_transaksi` | Jurnal/dokumen akuntansi | `REUSE` | Perlu posting source link dan unique source-event agar posting tidak ganda |
| `akunting.posting_history` | Riwayat posting | `REUSE/EXTEND` | Perlu correlation, source type/id, reversal relation, dan status kegagalan terstruktur |
| `akunting.uang_muka`, `pertangungjawaban` | Uang muka dan settlement | `REUSE` | Harus tetap domain terpisah dari AP invoice/payment |
| `akunting.kas_besar`, `pertangungjawaban_kas_besar` | Kas besar dan settlement | `REUSE` | Tidak boleh digabung dengan pembayaran vendor hanya karena sama-sama cash out |
| `akunting.kas_kecil`, `penggantian_kas_kecil` | Petty cash dan replenishment | `REUSE` | Replacement adalah aksi/lifecycle, bukan menu/tabel pengadaan baru |
| `dana_talangan`, `reimbursement_pegawai` | Talangan dan reimbursement | `REUSE` | Tetap terpisah dari uang muka dan AP |

### 3.4 Penjualan, laporan, serta hak akses

| Area existing | Keputusan | Catatan gap |
|---|---|---|
| Transaksi POS dan rincian penjualan | `REUSE + ALTER` | Tambahkan/validasi idempotency, origin device/user/store, business timestamp, sync state, serta posting link; jangan menyalin transaksi menjadi tabel laporan |
| Retur penjualan | `REUSE + ALTER` | Harus menunjuk transaksi/rincian asal dan membuat reversal ledger yang unik |
| `TbmroleAction`/role-menu existing | `REUSE + EXTEND` | Tetap sumber izin utama; butuh registry key kanonik dan alias legacy, bukan tabel izin paralel |
| Katalog laporan/dashboard | `PROJECT` | Query/read model dari transaksi canonical; tidak boleh menjadi sumber koreksi data |

## 4. Keputusan schema per domain blueprint

### 4.1 Master Data

| Target | Existing | Keputusan | Perubahan |
|---|---|---|---|
| Produk canonical | `koperasi.produk` | `REUSE + ALTER` | Tambahkan global/item identity bila belum ada, `base_uom_id`, version/optimistic lock, dan validasi unique code/barcode dalam scope tenant/toko |
| Kategori produk & akun | jenis produk dan akun existing | `REUSE + EXTEND` | Relasi akun inventory, COGS, revenue, retur, waste per kategori; jangan gabung dengan grup produk |
| Grup harga/HPP/resep | grup produk dan resep existing | `REUSE + EXTEND` | Tegaskan scope toko, effective date, formula/HPP method, dan versioning |
| UOM & konversi | satuan existing | `REUSE + NEW bridge` | Buat `item_uom_conversion(item_id, from_uom, to_uom, numerator, denominator, rounding_rule)` |
| Supplier/vendor | penyedia/supplier existing | `REUSE` | Tambahkan status approval, lead time, payment term default, tax identity bila belum ada |
| Outlet | `koperasi.toko` | `REUSE` | Menjadi business location; bukan bin stok |
| Gudang | `sirs.gudang` | `REUSE + EXTEND` | Tambahkan `toko_id`, `warehouse_type`, timezone, capability, active, code unique per tenant |
| Zona/bin | belum canonical | `NEW` | `warehouse_zone`, `warehouse_bin`; bin unique per gudang dan dapat menyimpan restriction/capacity |
| Armada/ekspedisi | sebagian master transport/vendor | `EXTEND/NEW` | `carrier`, `vehicle`, `driver` hanya bila master existing tidak memenuhi lifecycle distribusi |

### 4.2 Perencanaan & Replenishment

Permintaan stok outlet tidak boleh memakai tabel PR, karena sumber pemenuhan pertama
adalah stok internal, bukan vendor.

| Tabel target | Keputusan | Kolom minimum |
|---|---|---|
| `replenishment_policy` | `NEW`; mengembangkan konsep ambang stok | item, destination location, min, max, safety stock, reorder point, lead time, rounding/pack, preferred source, effective dates |
| `stock_request` | `NEW` | code, requester outlet/gudang, requested/needed time, priority, status, correlation, idempotency |
| `stock_request_line` | `NEW` | request, item, UOM, requested/approved/allocated/fulfilled/cancelled qty, source suggestion |
| `demand_consolidation` dan detail | `NEW` | window konsolidasi, request lines, hasil internal transfer vs procurement |
| `replenishment_proposal` dan detail | `NEW` | policy snapshot, on-hand/available/inbound, proposed qty, source, approval |
| `stock_allocation_plan` | `NEW` | demand line, source location, allocated qty, reservation/PR/transfer reference |

### 4.3 Pengadaan

#### Tabel existing yang dipertahankan

- `asset.permintaan_pengadaan_master_asset` sebagai header PR;
- `asset.pemesanan_pengadaan_master_asset` sebagai header PO/perjanjian;
- `asset.penerimaan_pengadaan_master_asset` sebagai dokumen BAST administratif;
- seluruh detail existing tetap untuk alur MasterAsset;
- `koperasi.pengadaan_produk` tetap menjadi direct purchase/Kulakan selama migrasi.

#### Tabel extension/bridge yang disarankan

| Tabel target | Relasi | Alasan |
|---|---|---|
| `procurement_document_extension` | unique `(document_type, legacy_document_id)` | Menambah source demand, destination warehouse/location, business status, correlation/idempotency tanpa ALTER besar pada tiga header legacy |
| `procurement_item_reference` | unique `(document_type, legacy_line_id)` | Discriminator `MASTER_ASSET/PRODUK/JASA/BIAYA`, reference id, UOM snapshot, precision qty; menghindari FK ambigu dalam detail legacy |
| `purchase_order_schedule` | PO/line | Delivery schedule dan milestone terstruktur; termin pembayaran tidak dijadikan jenis PO terpisah |
| `purchase_order_payment_term` | PO | Term, due rule, percentage/amount, milestone, retention |
| `rfq`, `rfq_line`, `rfq_vendor`, `vendor_quotation`, `vendor_quotation_line` | `NEW` | RFQ/seleksi vendor belum dimiliki tabel PR/PO |
| `procurement_status_history` | dokumen PR/PO/BAST | Audit lifecycle lintas platform dan actor |
| `procurement_legacy_map` | old type/id ke canonical type/id | Menjamin migrasi dapat diulang dan ditelusuri |

#### ALTER minimum yang aman pada header existing

Jika extension table dipilih, ALTER header dibatasi pada:

- `version_no` untuk optimistic locking;
- `created_at`, `updated_at` yang konsisten bila audit superclass belum menjamin;
- unique partial untuk `kode_unik/idempotency_key` jika kolom existing sudah ada;
- index pada foreign key dan kolom status/tanggal yang dipakai daftar kerja.

Jangan menambahkan seluruh kolom WMS ke header BAST. Receiving fisik, QC, dan
putaway tetap aggregate Pergudangan.

### 4.4 Pergudangan

| Tabel target | Existing/keputusan | Fungsi canonical |
|---|---|---|
| `inventory_movement` | `NEW`; backfill dari seluruh mutasi legacy | Ledger immutable untuk setiap event masuk/keluar/transfer/reserve/release/adjust/reverse |
| `inventory_balance` | `PROJECT` | Saldo per item-gudang-bin-batch-status; dapat dibangun ulang dari ledger |
| `inventory_reservation` | `NEW` | Reservasi terhadap demand/transfer/produksi/order, dengan allocate/release/consume |
| `warehouse_receipt` | `NEW` | Penerimaan fisik vendor/transfer/return; reference type/id ke BAST/shipment |
| `warehouse_receipt_line` | `NEW` | expected, received, accepted, rejected, damaged qty dan UOM |
| `quality_inspection` dan result | `NEW` | QC plan/result, disposition `ACCEPT/REJECT/QUARANTINE` |
| `putaway_task` dan detail | `NEW` | Perpindahan receiving dock ke bin |
| `inventory_lot` | `NEW/merge migration` dari `produk_batch` | Lot/batch canonical, manufacture/expiry, supplier lot, QC status |
| `inventory_serial` | `NEW` | Serial unik dan state/location history |
| `stock_count` dan `stock_count_line` | `EXTEND/NEW` dari sesi opname | Snapshot, blind count, recount, approval |
| `inventory_adjustment` dan detail | `NEW` | Dokumen approval adjustment; posting menghasilkan movement |
| `pick_wave`, `pick_task`, `pick_task_line` | `NEW` | Allocation-to-pick, lot/FEFO choice, short pick |
| `packing`, `package`, `package_item` | `NEW` | Hasil packing, weight/dimension/seal |
| `warehouse_return` dan detail | `NEW` | Retur internal gudang; vendor/customer return tetap aggregate asal |

#### ALTER/constraint lintas inventory

1. Quantity canonical: `numeric(18,4)`, bukan `double precision`.
2. Nilai uang: `numeric(18,2)` atau precision lebih besar sesuai standar Akuntansi.
3. `inventory_movement.quantity > 0`; arah disimpan pada `direction` atau signed qty,
   pilih satu saja dan konsisten.
4. Unique `idempotency_key` per tenant/source event.
5. Reversal menunjuk movement asal dan tidak mengubah baris asal.
6. `inventory_balance` unique pada dimensi item, gudang, bin, lot, serial/status stok.
7. `produk.stok`, `produk_batch.stok`, dan saldo mutasi lama diberi status
   `PROJECT/ADAPTER`; setelah cutover tidak boleh menjadi writer independen.

### 4.5 Distribusi & Pengiriman

`asset.pengiriman_gudang` tidak dihapus pada fase awal, tetapi tidak cukup menjadi
semua dokumen distribusi.

| Tabel target | Keputusan | Batas tanggung jawab |
|---|---|---|
| `stock_transfer` dan line | `NEW` | Komitmen pemindahan antar lokasi dari stock request/allocation |
| `delivery_order` dan line | `NEW` | Perintah outbound terhadap transfer/order; sumber picking |
| `freight_order` | `NEW` | Pemesanan jasa/armada/rute/muatan; bukan PO barang |
| `shipment` | `NEW` | Eksekusi pengiriman fisik dan status tracking |
| `shipment_package` | `NEW` | Paket yang dibawa shipment |
| `shipment_leg` | `NEW` | Multi-leg/transit/carrier dan planned/actual time |
| `shipment_event` | `NEW` | Event tracking immutable |
| `proof_of_delivery` | `NEW` | Bukti tiba, actor, waktu, geolocation, signature/photo/document ref |
| `outlet_transfer_receipt` dan line | `NEW` | Penerimaan oleh outlet, accepted/damaged/short/over qty |
| `distribution_claim` | `NEW` | Selisih, rusak, hilang, claim resolution |
| `reverse_logistics` dan line | `NEW` | Retur transfer/outlet ke gudang, tidak memakai retur pembelian/penjualan |

Mapping legacy dilakukan dengan `delivery_legacy_map` ke
`asset.pengiriman_gudang`. Selama dual-write, idempotency key yang sama wajib
mencegah satu pengiriman menghasilkan dua movement.

### 4.6 Produksi

| Tabel target | Keputusan | Catatan |
|---|---|---|
| `bill_of_material` dan line | `NEW/EXTEND` dari resep existing | Versioned, effective date, output item/UOM, ingredient dan expected waste |
| `production_plan` dan line | `NEW` | Rencana berbasis demand/replenishment |
| `production_order` | `NEW` | Work order, lokasi, batch output, planned/actual times, status |
| `material_reservation` | `NEW` atau subtype inventory reservation | Bahan yang dicadangkan untuk order |
| `material_issue`/`material_return` | `NEW` | Dokumen pengeluaran/pengembalian bahan; menghasilkan movement |
| `production_output` | `NEW` | Finished/semi-finished goods receipt |
| `production_waste` | `NEW` | Waste/scrap/rework dengan reason dan cost |
| `production_cost_snapshot` | `NEW/PROJECT` | Material, labor, overhead, yield untuk posting HPP |

`Barang Dalam Proses` pada menu Pengadaan tidak boleh menjadi production WIP.
Monitoring PO belum datang tetap milik Pengadaan; WIP/CIP produksi/aset memiliki
source document dan akun berbeda.

### 4.7 Keuangan/AP

| Tabel target | Existing/keputusan | Catatan |
|---|---|---|
| `ap_invoice` | `NEW`; migrasi dari `saldo_awal_master_asset` yang benar-benar invoice | Vendor invoice canonical, invoice number/date, due date, currency/rate, tax, total, open amount, status |
| `ap_invoice_line` | `NEW` | Item/expense/tax, qty, price, PO/receipt line match |
| `ap_match_result` | `NEW` | Hasil 2-way/3-way match dan toleransi |
| `ap_dispute` | `NEW` | Mismatch, hold, resolution |
| `ap_payment_schedule` | `NEW` | Termin invoice yang jatuh tempo; tidak menduplikasi PO term |
| `ap_payment_allocation` | `NEW` | Proses/daftar transfer ke invoice/credit note dan amount allocated |
| `ap_credit_note` dan line | `NEW` | Credit note vendor/retur yang mengurangi AP |
| `payment_execution` | `EXTEND` dari proses transfer | Referensi bank, status submit/success/fail/reconcile dan idempotency |

Strategi migrasi `saldo_awal_master_asset`:

1. klasifikasikan record saldo awal murni versus invoice vendor;
2. migrasikan hanya invoice vendor ke `ap_invoice`;
3. simpan `legacy_type`, `legacy_id`, dan checksum;
4. bandingkan total, sisa, termin, dan allocation;
5. layar lama membaca view kompatibilitas selama masa transisi;
6. hentikan write invoice baru ke tabel lama setelah UAT AP lulus.

### 4.8 Akuntansi

Tabel jurnal existing tetap canonical. Yang ditambahkan adalah hubungan deterministik
dengan source event.

| Tabel target | Keputusan | Fungsi |
|---|---|---|
| `accounting_posting_link` | `NEW` | unique source domain/type/id/event ke journal group/id |
| `accounting_posting_job` | `NEW` | Job queue, attempt, status, error, next retry |
| `accounting_reversal_link` | `NEW` | Jurnal balik terhadap posting asal |
| `inventory_valuation_layer` | `NEW` | Layer cost FIFO/average/specific sesuai kebijakan item |
| `accounting_period_lock` | `EXTEND/NEW` dari closing existing | Lock per entity/location/domain dan audit override |

Posting tidak boleh mengubah dokumen bisnis asal. Unique source event mencegah
double posting ketika worker retry.

### 4.9 Laporan dan Control Tower

| Read model target | Sumber | Implementasi |
|---|---|---|
| `mv_inventory_position` | movement + balance + reservation | Materialized/read model, refresh incremental |
| `mv_procurement_pipeline` | PR/PO/schedule/receipt/invoice/payment | SLA dari request sampai bayar |
| `mv_distribution_pipeline` | transfer/DO/pick/pack/shipment/POD | Fill rate, OTIF, lead time, claim |
| `mv_production_performance` | production order/issue/output/waste | Yield, waste, plan vs actual |
| `mv_finance_exposure` | AP/AR/cash/posting | Aging dan unpaid exposure |
| `exception_event` | seluruh domain | Alert unresolved, severity, owner, SLA, resolved state |

Semua read model harus dapat dihapus dan dibangun ulang. Koreksi dilakukan pada
dokumen asal atau reversal, bukan dengan mengedit angka dashboard.

### 4.10 Sistem, menu, dan hak akses

`TbmroleAction` tetap sumber izin utama. Tambahkan registry, jangan membuat sistem
role kedua.

| Tabel target | Keputusan | Kolom minimum |
|---|---|---|
| `app_menu_registry` | `NEW` | menu_key, parent_key, label, canonical_route, sort_order, platforms, feature_flag, active |
| `app_action_registry` | `NEW` | action_key, menu_key/domain, risk level, description, active |
| `app_action_alias` | `NEW` | legacy action/menu key, canonical action key, deprecated/replacement metadata |
| role-action existing (`TbmroleAction`) | `REUSE + ALTER/bridge` | Referensi canonical action key bila struktur mengizinkan; bila tidak, bridge `role_action_canonical_map` |
| `workflow_history` | `NEW` lintas domain | document type/id, from/to status, action, actor, time, reason |
| `audit_event` | `NEW/EXTEND` | tenant, actor, device, action, entity, before/after hash, correlation |
| `outbox_event` | `NEW` | event publication transactional, status/attempt/next retry |

`Common.apakahAdmin() == true` merupakan override akses menu/action seperti yang
ditetapkan blueprint, tetapi setiap mutasi berisiko tetap dicatat di audit event.

## 5. Matriks existing ke target

| Existing | Target canonical | Keputusan migrasi |
|---|---|---|
| PR MasterAsset header/detail | PR existing + procurement extension/item reference | Header `REUSE`; detail MasterAsset tetap; tipe item baru melalui bridge |
| PO MasterAsset header/detail | PO existing + schedule/payment term/extension | `REUSE + EXTEND`; termin bukan tabel/menu PO kedua |
| Penerimaan MasterAsset/BAST | BAST administratif + warehouse receipt/QC/putaway | `REUSE` BAST; WMS `NEW`; link one-to-many |
| SaldoAwalMasterAsset sebagai invoice | `ap_invoice`/line | Migrasi terklasifikasi; legacy `ADAPTER`, lalu `RETIRE-WRITE` |
| ProsesTransfer/DaftarPengajuanTransfer | payment execution + AP payment allocation | `REUSE + EXTEND` |
| PengadaanProduk/PengadaanFaktur | direct purchase/Kulakan + receipt/movement/posting link | `REUSE` jalur sederhana; jangan menjadi PO enterprise |
| Produk.stok | inventory balance | `PROJECT`; hentikan writer independen |
| ProdukBatch/MutasiProdukBatch | inventory lot + movement + balance | Migrasi/backfill; legacy adapter |
| MutasiStokToko | stock transfer + shipment + receipt + movement | Pecah aggregate; dual-write sementara |
| StokOpname/SesiStokOpname | stock count + adjustment + movement | Reuse header bila aman, tambah detail/workflow canonical |
| AmbangStokGudang | replenishment policy | Migrasi min threshold, lengkapi max/safety/lead time |
| PengirimanGudang | transfer/DO/shipment/POD | Adapter legacy, bukan target tunggal |
| ReturPembelian | purchase return + AP credit + movement reversal | `REUSE + EXTEND` |
| ReturPenjualan | sales return + refund/credit + movement reversal | `REUSE + EXTEND` |
| TbmroleAction | role action canonical + registry/alias | `REUSE`; migrasi alias bertahap |

## 6. Kolom dan constraint lintas tabel

Semua tabel transaksi baru sekurang-kurangnya memiliki:

- `id` bigint/UUID sesuai standar platform;
- `tenant_id` atau schema tenant yang tidak ambigu;
- `code`/nomor dokumen unique pada scope yang disepakati;
- `business_at`, `created_at`, `updated_at`;
- `created_by`, `updated_by`, `approved_by` bila relevan;
- `status` dengan state machine terdokumentasi;
- `version_no` untuk optimistic locking;
- `idempotency_key` unique;
- `correlation_id`, `causation_id` untuk rantai proses;
- `source_type`, `source_id` untuk dokumen asal;
- `origin_device_id`, `origin_user_id`, `origin_store_id` untuk transaksi offline/POS;
- `cancelled_at/by/reason`, tanpa hard delete transaksi;
- audit metadata yang tidak menyimpan payload sensitif secara sembarang.

Constraint minimum:

1. seluruh foreign key yang bersifat wajib dibuat `NOT NULL` setelah data legacy
   dibersihkan;
2. angka quantity/value memakai `CHECK` sesuai semantik dan numeric precision;
3. status transition divalidasi service dan, untuk invariants kritis, constraint;
4. unique idempotency dan posting source;
5. unique business key pada code/barcode/invoice number sesuai scope;
6. partial unique untuk satu reservation aktif atau satu open document bila aturan
   bisnis memerlukannya;
7. delete master yang sudah direferensikan ditolak atau memakai soft deactivate.

Index minimum:

- semua foreign key;
- `(tenant/location, status, business_at)` pada work queue;
- `(item_id, warehouse_id, bin_id, lot_id)` pada inventory;
- `(source_type, source_id)` dan `correlation_id`;
- vendor + invoice number/date;
- due date + open status pada AP;
- shipment tracking number/status;
- outbox status + next attempt;
- report range berdasarkan business date, bukan fungsi pada kolom tanggal.

## 7. Ownership dan larangan penulisan ganda

| Kejadian | Writer canonical | Writer yang dilarang setelah cutover |
|---|---|---|
| Vendor diterima | Warehouse receipt posting service | BAST, produk, dan batch masing-masing mengubah stok sendiri |
| Transfer dikirim | Shipment/stock transfer posting service | MutasiStokToko langsung menambah/mengurangi kedua toko |
| Outlet menerima | Outlet receipt posting service | POD hanya mengubah status tanpa ledger, atau outlet mengedit stok langsung |
| Produksi issue/output | Production inventory posting service | Formula/resep langsung mengubah stok |
| Penjualan POS | Sales posting/outbox idempotent | UI dan sync worker membuat transaksi server kedua |
| Stock opname | Approved adjustment posting service | Edit `produk.stok` langsung |
| Invoice diterima | AP invoice service | PO/BAST/SaldoAwal masing-masing membentuk utang terpisah |
| Pembayaran | Payment allocation/posting service | Transfer dan invoice mengurangi saldo secara independen |

Selama dual-write, writer lama hanya dipanggil melalui adapter dari satu service
canonical dalam transaksi yang terkontrol. Tidak boleh ada dua listener independen
yang membuat event bisnis sama.

## 8. Urutan migrasi schema yang disarankan

Urutan ini diselaraskan dengan Fase 0–14 pada blueprint menu.

### Fase data 0 — Baseline dan keputusan

1. snapshot schema, constraint, index, row count, size, null ratio, duplicate business
   key, dan orphan FK;
2. daftar seluruh writer SQL/Hibernate untuk stok, PR/PO/BAST, invoice, transfer,
   payment, dan jurnal;
3. kunci pilihan schema tenant, precision, ID strategy, timezone, dan owner tiap
   aggregate;
4. buat reconciliation query/golden dataset.

### Fase data 1 — Registry dan otorisasi

1. buat menu/action registry serta alias;
2. mapping `TbmroleAction` existing;
3. validasi admin override dan action granular;
4. belum memindahkan data bisnis.

### Fase data 2 — Fondasi master dan item reference

1. normalisasi relasi toko-gudang-zona-bin;
2. buat UOM conversion;
3. buat procurement document extension dan item reference;
4. backfill mapping `MasterAsset`/`Produk` tanpa menyatukan identity secara paksa.

### Fase data 3 — Ledger dan saldo inventory

1. buat movement, balance, lot/serial, reservation;
2. backfill dari produk, batch, mutasi, opname, kulakan, penjualan, dan retur;
3. reconcile per item-lokasi-tanggal;
4. aktifkan shadow posting dan bandingkan;
5. cutover writer per event, bukan sekaligus.

### Fase data 4 — Replenishment dan procurement extension

1. buat policy, stock request, consolidation, proposal, allocation;
2. buat RFQ, PO schedule, dan payment term;
3. hubungkan demand kurang stok ke PR existing melalui extension;
4. UAT stock available vs procurement fallback.

### Fase data 5 — WMS inbound dan outbound

1. receipt, QC, putaway;
2. picking, packing, transfer;
3. migration adapter BAST dan PengirimanGudang;
4. UAT partial/over/short/damaged/lot/expiry.

### Fase data 6 — Distribusi dan produksi

1. DO, FO, shipment, tracking, POD, outlet receipt, claim, reverse logistics;
2. BOM, production order, material issue/return, output, waste;
3. UAT end-to-end gudang-outlet-produksi-POS.

### Fase data 7 — AP, payment, dan posting

1. klasifikasi/migrasi SaldoAwalMasterAsset;
2. AP invoice, match, dispute, schedule, allocation;
3. accounting posting link/job/reversal dan valuation layer;
4. reconcile AP subledger ke GL sebelum retire-write.

### Fase data 8 — Read model, UAT, dan dekomisioning

1. build materialized/read models;
2. UAT seluruh platform Desktop, Android, JSP, dan ZKoss;
3. observasi dual-write minimal satu periode operasi yang disepakati;
4. tandai tabel/kolom legacy read-only;
5. penghapusan fisik hanya pada release terpisah setelah backup dan sign-off.

## 9. Query audit yang wajib tersedia sebelum DDL

Migration package berikutnya wajib menyertakan query untuk:

1. PR detail tanpa header, PO detail tanpa header, BAST detail tanpa header;
2. PO tanpa PR yang memang direct/exception versus data orphan;
3. receipt quantity melebihi PO tanpa exception reason;
4. invoice vendor tanpa BAST/PO dan duplicate vendor-invoice-number;
5. payment allocation melebihi open amount;
6. produk/batch/mutasi dengan saldo berbeda;
7. stock negatif dan event tanpa source document;
8. transfer kirim tanpa penerimaan atau penerimaan melebihi kirim;
9. batch kedaluwarsa/karantina yang masih available;
10. movement/posting duplikat berdasarkan source dan idempotency;
11. jurnal tidak balance atau source event tanpa journal saat wajib posting;
12. role action legacy yang tidak mempunyai canonical alias.

Setiap backfill harus menghasilkan tabel kontrol minimal:

`entity_type`, `legacy_id`, `target_id`, `checksum_before`, `checksum_after`,
`migration_batch`, `migrated_at`, dan `status/error`.

## 10. Risiko dan mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Memaksa Produk masuk ke FK MasterAsset | Identitas/akuntansi salah | Item discriminator + reference bridge |
| Mengubah PR/PO/BAST sekaligus | Workflow existing rusak | Extension table dan adapter bertahap |
| Menjadikan BAST sekaligus receiving/QC/putaway | Partial receiving tidak terlacak | Pisahkan dokumen administratif dan eksekusi WMS |
| Tetap memakai SaldoAwal sebagai invoice | AP sulit diaudit | Migrasi ke AP invoice canonical |
| Produk.stok tetap dapat ditulis banyak modul | Saldo drift | Satu posting service + ledger + rebuildable projection |
| PengirimanGudang menjadi DO+shipment+POD | Status ambigu | Aggregate terpisah dengan reference chain |
| Report memperbaiki data transaksi | Audit trail hilang | Koreksi/reversal pada source document |
| Menambah sistem hak akses baru | Role ganda dan menu berbeda antar platform | Registry/alias di atas TbmroleAction existing |
| Tabel harian untuk volume | Query UNION dan migration kompleks | Tabel stabil + index; partition bulanan setelah benchmark |
| Dual-write tanpa idempotency | Stok/jurnal ganda | Unique source-event/idempotency dan reconciliation |

## 11. Keputusan yang harus dikunci sebelum migration SQL

1. Apakah tabel target memakai schema tenant `{S}` atau schema domain bersama dengan
   `tenant_id`? Jangan mencampur keduanya tanpa aturan.
2. Identitas canonical item lintas toko: apakah `koperasi.produk` langsung, master
   global + SKU outlet, atau bridge existing?
3. Hubungan resmi `MasterAsset` terhadap `Produk`: terpisah total, optional mapping,
   atau subtype item master.
4. Precision quantity dan currency untuk semua domain.
5. Metode valuasi per item/lokasi dan kapan layer cost dikunci.
6. Batas administrasi BAST versus receiving fisik.
7. Lifecycle tagihan lama yang dikategorikan invoice versus saldo awal murni.
8. Nomor dokumen dan timezone/business date per unit usaha.
9. Retensi event, audit, payload outbox, foto/signature POD.
10. Durasi dual-write, toleransi reconciliation, dan rollback criterion.

## 12. Definition of Ready untuk coding schema

Coding migration boleh dimulai bila:

- owner setiap aggregate dan satu-satunya writer disetujui;
- ERD target dan state machine dokumen disetujui;
- data dictionary kolom, type, nullability, FK, unique, check, dan index tersedia;
- mapping setiap tabel/kolom legacy ke target lengkap;
- volume, query utama, dan partition decision terukur;
- backfill/reconciliation/rollback script dirancang;
- kontrak API dan action permission per menu tersedia;
- UAT mencakup happy path, partial, reject, cancel, reverse, retry, dan offline sync;
- Java 1.7/server legacy dan seluruh client mendapat strategi kompatibilitas;
- tidak ada tabel baru yang hanya menduplikasi nama menu.

## 13. Rekomendasi eksekutif

Implementasi paling aman bukan mengganti seluruh tabel existing dan bukan pula
menambahkan semua kebutuhan ke tabel lama. Gunakan pola **reuse header yang matang,
extension untuk kompatibilitas, aggregate baru untuk lifecycle baru, serta adapter
yang dapat dihentikan**.

Prioritas teknis pertama adalah menu/action registry, item identity, gudang/bin,
inventory ledger, dan idempotency. Setelah fondasi ini stabil, replenishment,
receiving/QC/putaway, distribusi, produksi, AP, dan posting dapat ditambahkan tanpa
menciptakan stok, tagihan, pembayaran, atau jurnal ganda.

Dokumen lanjutan yang harus dibuat sebelum coding adalah:

1. ERD target fisik;
2. data dictionary dan state machine;
3. mapping legacy-to-target per kolom;
4. draft migration V1 yang hanya additive;
5. paket query audit/reconciliation; dan
6. rencana UAT serta cutover per writer.
