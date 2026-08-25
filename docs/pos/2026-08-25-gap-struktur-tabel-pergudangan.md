# Gap analysis struktur tabel Pergudangan

Tanggal: 25 Agustus 2026  
Status: **analisis desain; belum ada perubahan schema/database**  
Dokumen induk: [Analisis implementasi modul Pergudangan](2026-08-25-analisis-modul-pergudangan.md)  
Rencana pelaksanaan: [Fase implementasi modul Pergudangan](2026-08-25-fase-implementasi-modul-pergudangan.md)

## 1. Tujuan dan batas analisis

Dokumen ini membandingkan struktur data inventory yang sudah ada dengan kebutuhan
struktur data modul Pergudangan/WMS yang akan dibangun. Tujuannya adalah menentukan
bagian yang dapat dipakai ulang, bagian yang harus diperluas, dan tabel baru yang
benar-benar diperlukan tanpa membuat sumber saldo stok paralel.

Analisis dibuat dari:

- anotasi entity Hibernate/JPA pada repository server `C:\opt\AIS\ais`;
- migration tenant pada `TenantSchemaMigrationsV2` dan
  `TenantSchemaMigrationsV3`;
- alur POS, pengadaan, transfer toko, batch, kedaluwarsa, retur, dan stock opname
  yang telah tersedia;
- kebutuhan proses pada dokumen referensi modul Pergudangan.

Dokumen ini **bukan hasil introspeksi database produksi**. Nama kolom, constraint,
index, nullability, jumlah baris, dan kualitas data aktual tetap harus diverifikasi
dengan query katalog PostgreSQL pada Fase 0 sebelum migration dijalankan.

## 2. Kesimpulan eksekutif

Fondasi inventory sebenarnya sudah cukup banyak, tetapi terpecah menjadi tiga jalur:

1. model shared/legacy pada schema `koperasi`, `asset`, dan `sirs`;
2. schema tenant baru dengan tabel `gudang`, `lokasi_stok`, `mutasi_stok`,
   `saldo_stok`, `produk_batch`, dan `stok_opname`;
3. kebutuhan WMS lanjutan yang belum memiliki struktur lengkap, seperti reservasi,
   penerimaan dan QC, putaway, picking, serial number, serta cost layer.

Karena itu, gap terbesar bukan sekadar “belum ada tabel gudang”. Gap terbesarnya
adalah **belum ditetapkannya satu kontrak inventory kanonis** yang digunakan semua
jalur transaksi. Implementasi tidak boleh menambahkan ledger stok ketiga.

Rekomendasi utama:

- jadikan tabel tenant `mutasi_stok` sebagai kandidat ledger kanonis karena sudah
  memiliki dimensi gudang, lokasi, batch, sumber dokumen, reversal, idempotency, dan
  correlation ID;
- jadikan `saldo_stok` hanya proyeksi/cache yang dapat dibangun ulang dari ledger,
  bukan sumber kebenaran kedua;
- adaptasikan data shared/legacy melalui mapper dan backfill bertahap;
- perluas schema tenant dengan tabel proses WMS yang belum tersedia;
- gunakan `numeric(18,4)` untuk kuantitas dan `numeric(18,2)` untuk nilai uang;
- jangan membuat tabel fisik harian seperti `transaksi_DD_MM_YYYY`; gunakan tabel
  stabil dan partitioning bulanan hanya jika volume aktual membutuhkannya.

## 3. Peta struktur existing

### 3.1 Tiga lapisan yang saat ini hidup berdampingan

| Lapisan | Lokasi | Karakter | Risiko utama |
|---|---|---|---|
| Shared/legacy | `sirs`, `asset`, `koperasi` | Entity Hibernate yang dipakai fitur lama | Relasi lintas domain, banyak angka `Double`, dan dimensi lokasi belum konsisten |
| Tenant ERP | schema dinamis `{S}` melalui migration V2/V3 | Struktur lebih presisi dan siap multi-tenant | Belum seluruh alur lama menulis ke sini; beberapa constraint masih hanya index biasa |
| WMS yang direncanakan | Belum dibuat | Receiving, QC, putaway, reservation, picking, serial, costing | Berisiko menjadi stack ketiga jika tidak memakai ledger tenant sebagai fondasi |

### 3.2 Inventory tabel/model shared dan legacy

| Tabel existing | Model/package | Isi penting | Penilaian |
|---|---|---|---|
| `sirs.gudang` | `ais.database.model.sirs.Gudang` | `kode`, `nama`, `alamat`, `keterangan`, `gudang_induk`, `aktif` | Dapat menjadi sumber migrasi. Package `sirs` membuat ownership gudang bercampur dengan domain medis dan `kode` unik global, bukan per tenant/toko. |
| `asset.lokasi` | `ais.database.model.asset.Lokasi` | identitas lokasi, alamat/koordinat/IP, relasi `gudang`, `toko`, `jenis_lokasi` | Berguna untuk lokasi fisik umum, tetapi terlalu lebar untuk bin stok. Tidak memiliki kode bin, parent path, kapasitas, aturan mixing, dan status blokir inventory. |
| `asset.pengiriman_gudang` | `ais.database.model.asset.PengirimanGudang` | kode, lokasi asal/tujuan/transit, tanggal kirim/terima, status, pengirim/penerima | Fondasi header transfer yang baik. Belum terlihat kontrol idempotency, approval, shipment lifecycle formal, nomor eksternal, dan kaitan ke movement ledger. |
| `asset.pengiriman_gudang_detail` | `ais.database.model.asset.PengirimanGudangDetail` | produk, qty kirim/terima/rusak, harga satuan, alasan rusak | Fondasi detail transfer. Kuantitas/harga masih `Double`; belum memiliki batch, serial, UOM snapshot, source/destination bin, dan reason code terstruktur. |
| `koperasi.mutasi_stok_toko` | `ais.database.model.inventory.MutasiStokToko` | produk/toko asal dan tujuan, qty, waktu, keterangan | Mendukung transfer antar-toko, bukan ledger WMS per lokasi. Tidak ada status, pasangan debit/kredit, batch, idempotency, atau reversal. |
| `koperasi.produk_batch` | `ais.database.model.inventory.ProdukBatch` | produk, toko, nomor batch, produksi, expired, stok, harga modal, status | Fondasi lot/expiry. Menyimpan `stok` mutable sehingga dapat bersaing dengan ledger; belum berdimensi gudang/lokasi dan tidak mencakup serial. |
| `koperasi.mutasi_produk_batch` | `ais.database.model.inventory.MutasiProdukBatch` | batch, waktu, jenis, masuk, keluar, saldo, referensi | Audit batch dasar. Belum memiliki gudang/lokasi, sumber dokumen bertipe, idempotency, reversal, dan nilai finansial presisi. |
| `koperasi.sesi_stok_opname` | `ais.database.model.inventory.SesiStokOpname` | toko, kode, jadwal/mulai/selesai, kategori, petugas, status | Dapat dipakai sebagai sumber migrasi header opname. Belum mengikat gudang/lokasi serta watermark snapshot dan approval/recount. |
| `koperasi.stok_opname` | `ais.database.model.inventory.StokOpname` | produk, toko, stok sistem/fisik, selisih, waktu, alasan | Menyediakan hasil hitung sederhana. Belum terkait sesi secara eksplisit pada field yang diaudit, batch/lokasi, freeze/watermark, dan movement posting. |
| `koperasi.ambang_stok_gudang` | `ais.database.model.inventory.AmbangStokGudang` | produk, gudang, ambang minimum, aktif, keterangan | Dapat menjadi sumber reorder minimum. Belum ada maksimum, safety stock, lead time, supplier utama, metode replenishment, dan satuan. |
| `koperasi.pengadaan_faktur` | `ais.database.model.inventory.PengadaanFaktur` | toko, supplier, nomor/tanggal faktur, total manual/hitung, diskon | Dokumen sumber pembelian. Belum menjadi dokumen penerimaan gudang/QC dan nilai masih `Double`. |
| `koperasi.pengadaan_produk` | `ais.database.model.inventory.PengadaanProduk` | produk/toko/supplier/faktur, qty, harga beli, total, waktu | Detail barang masuk. Belum memisahkan ordered/received/accepted/rejected/putaway dan belum berdimensi batch/lokasi. |
| `koperasi.retur_pembelian` | `ais.database.model.inventory.ReturPembelian` | produk/toko/supplier/faktur, qty, harga, total, alasan | Dokumen sumber pengeluaran retur supplier; membutuhkan link posting movement yang idempotent. |
| `koperasi.retur_penjualan` | `ais.database.model.inventory.ReturPenjualan` | produk/toko/transaksi asal, qty/nilai, kondisi, kembali ke stok | Dokumen sumber barang kembali; membutuhkan disposition QC: restock, quarantine, repair, atau scrap. |
| `koperasi.toko` | `ais.database.model.inventory.Toko` | identitas outlet dan `gudang_pemasok` | Dapat mengikat outlet ke default warehouse, tetapi belum menentukan default receiving, picking, return, dan quarantine location. |

### 3.3 Struktur tenant yang sudah tersedia

Migration V2/V3 sudah menyediakan fondasi yang lebih dekat ke WMS:

| Tabel tenant existing | Kolom utama yang sudah ada | Kekuatan | Gap tersisa |
|---|---|---|---|
| `{S}.gudang` | `kode`, `nama`, `toko_id`, `alamat`, `tipe`, `aktif`, audit | Sudah tenant scoped dan terkait toko | Belum ada parent, timezone, default locations, capacity, ownership, serta kebijakan negative stock |
| `{S}.lokasi_stok` | `kode`, `nama`, `gudang_id`, `aktif`, audit | Unique `(gudang_id, kode)` sudah tepat | Belum ada hirarki, tipe, barcode, urutan picking, kapasitas, allow-mix, quarantine/block state |
| `{S}.produk_batch` | `produk_id`, `batch_no`, `expiry_date`, `harga_beli`, aktif, legacy source | Presisi uang sudah `numeric`; siap migrasi | Belum ada warehouse/location ownership, manufacture/received date, supplier lot, QC status; batch number belum unique scoped |
| `{S}.mutasi_stok` | produk, gudang, lokasi, batch, tanggal, jenis, arah, kuantitas, harga/nilai, dokumen, reversal, idempotency, correlation, audit | Kandidat kuat ledger kanonis | Hanya `date`, bukan business timestamp; idempotency hanya diberi index non-unique; belum ada location asal/tujuan dalam satu event, UOM snapshot, actor/device, status posting, dan cost layer |
| `{S}.saldo_stok` | produk, gudang, lokasi, batch, kuantitas, nilai, waktu hitung | Proyeksi saldo multidimensi | Belum ada unique key dimensi, version/watermark, reserved/available qty, dan aturan rebuild |
| `{S}.stok_opname` | nomor, tanggal, gudang, status, keterangan, posting | Header opname lebih baik | Nomor belum unique; belum ada scope lokasi, freeze/watermark, assigned team, approval, recount, cancellation/reversal |
| `{S}.stok_opname_detail` | produk, batch, lokasi, qty sistem/fisik/selisih, harga, keterangan | Detail sudah berdimensi batch/lokasi | Belum ada unique line scope, count sequence, blind count, reason code, approval, dan movement posting link |

## 4. Gap struktur per kapabilitas WMS

### 4.1 Master gudang dan lokasi

| Kebutuhan target | Existing terdekat | Gap | Rekomendasi |
|---|---|---|---|
| Gudang per tenant/toko | `{S}.gudang`, `sirs.gudang` | Dua master gudang dengan identitas berbeda | Tetapkan `{S}.gudang` sebagai target; simpan legacy ID pada mapping/backfill, jangan sinkron dua arah permanen |
| Hirarki gudang/zone/aisle/rack/bin | `sirs.gudang.gudang_induk`, `{S}.lokasi_stok` | Hirarki hanya ada di master lama dan belum cukup untuk bin | Tambah `parent_id`, `tipe`, `path`, `level`, `urutan_picking` pada lokasi tenant |
| Barcode lokasi | Tidak ditemukan pada lokasi stok tenant | Scan putaway/picking tidak dapat divalidasi | Tambah `barcode` unique per tenant/gudang |
| Kapasitas dan compatibility | Tidak tersedia | Tidak dapat mencegah overload/mixing | Tambah kapasitas berat/volume/qty, `allow_mixed_product`, `allow_mixed_lot` secara nullable |
| Lokasi sistem | Hanya relasi umum | Receiving, staging, quarantine, return, damage belum terstandar | Tambah `tipe` dan flag/default location pada gudang atau tabel kebijakan gudang |

### 4.2 Ledger pergerakan dan saldo

| Kebutuhan target | Existing terdekat | Gap | Rekomendasi |
|---|---|---|---|
| Ledger immutable | `{S}.mutasi_stok` | Belum ada constraint yang melarang update/delete | Semua koreksi melalui reversal; batasi update/delete lewat service dan audit/trigger bila disetujui |
| Waktu bisnis presisi | `tanggal date` | Transaksi dalam hari yang sama tidak terurut akurat | Tambah `waktu_transaksi timestamp` dan pertahankan `tanggal` untuk filter/partition |
| Idempotency kuat | `idempotency_key` dengan index biasa | Duplikasi masih mungkin saat retry | Buat unique partial index untuk nilai non-null dan bentuk key dari source document + line + event |
| Perpindahan asal/tujuan | Satu `gudang_id` dan `lokasi_stok_id` per baris | Transfer perlu dua baris yang harus atomik | Gunakan `correlation_id` dan pasangan OUT/IN; opsional tambah header `inventory_transfer` |
| UOM dan konversi | Tidak ada pada movement | Audit kuantitas berubah jika master konversi diubah | Simpan `uom_id`, `qty_input`, `conversion_factor`, `qty_base` snapshot |
| Saldo tersedia | `{S}.saldo_stok.kuantitas` | Belum memisahkan on-hand, reserved, available, damaged, quarantine | Saldo on-hand tetap projection; reservasi di tabel terpisah; view menghitung available |
| Konsistensi proyeksi | `saldo_stok` tanpa unique dimensi/watermark | Duplikasi row saldo dan drift mungkin terjadi | Unique normalized dimension key + `ledger_watermark_id`/version dan job reconciliation |

### 4.3 Receiving, QC, dan putaway

Existing `pengadaan_faktur`/`pengadaan_produk` mencatat pengadaan, tetapi belum
merepresentasikan proses fisik penerimaan. Dibutuhkan struktur proses baru:

| Tabel logis target | Fungsi | Relasi existing | Status |
|---|---|---|---|
| `penerimaan_gudang` | Header penerimaan dari PO/faktur/transfer/return | Referensi ke pengadaan atau transfer, bukan menggantikannya | Baru |
| `penerimaan_gudang_detail` | Ordered, received, accepted, rejected per produk/UOM | Dapat dibentuk dari `pengadaan_produk` | Baru |
| `penerimaan_qc` | Hasil pemeriksaan, reason, foto/dokumen, keputusan | Retur sudah menyimpan alasan tetapi bukan QC inbound | Baru |
| `putaway_task` | Memindahkan barang dari receiving/staging ke bin | Tidak ada padanan | Baru |
| `putaway_task_detail` | Produk/batch/serial, asal, tujuan, qty, status | Posting ke `mutasi_stok` secara idempotent | Baru |

Kolom wajib lintas tabel proses: `nomor_dokumen`, `status`, `source_type`,
`source_id`, `toko_id`, `gudang_id`, waktu bisnis, pembuat/pelaksana/penyetuju,
`idempotency_key`, `correlation_id`, audit timestamp, serta version untuk optimistic
locking.

### 4.4 Transfer dan pengiriman gudang

`asset.pengiriman_gudang` dan detailnya dapat menjadi sumber migrasi atau adapter,
tetapi struktur target perlu memisahkan permintaan, pengiriman, penerimaan, dan
posting stok.

| Gap | Dampak | Target |
|---|---|---|
| Status berupa string bebas | State dapat dilewati/tidak konsisten | State machine: DRAF, DIAJUKAN, DISETUJUI, DIPICKING, DIKIRIM, DITERIMA_SEBAGIAN, DITERIMA, DIBATALKAN |
| Detail tidak memiliki batch/serial/bin | Traceability hilang | Tambah dimensi batch, serial, lokasi asal/tujuan pada allocation/execution line |
| `lokasi_transit` dinyatakan non-null pada entity | Transfer langsung dapat dipaksa membuat lokasi semu | Jadikan transit opsional atau modelkan shipment leg terpisah |
| Qty/harga `Double` | Risiko rounding | Migrasi ke `numeric`/`BigDecimal` |
| Tidak ada link movement | Dokumen dan ledger dapat berbeda | Simpan `posting_correlation_id` dan unique source line event |

Rekomendasi target: pertahankan dokumen legacy selama transisi, lalu gunakan
`transfer_gudang` + `transfer_gudang_detail` sebagai dokumen operasional tenant.
Movement OUT/IN tetap dicatat pada ledger kanonis, bukan dihitung langsung dari
status dokumen.

### 4.5 Reservasi, allocation, picking, packing, dan shipment

Kapabilitas berikut belum memiliki tabel existing yang memadai:

| Tabel logis target | Fungsi minimal |
|---|---|
| `reservasi_stok` | Menahan qty produk/batch/lokasi untuk order dengan expiry dan status |
| `reservasi_stok_detail` | Allocation aktual per bin/batch/serial |
| `picking_wave` | Pengelompokan order yang diproses bersama |
| `picking_task` | Tugas per petugas/zone dengan prioritas dan status |
| `picking_task_detail` | Expected/picked/short qty serta scan evidence |
| `packing` dan `packing_detail` | Hasil pengepakan, paket, berat/dimensi, pengecualian |
| `shipment` dan `shipment_package` | Kurir, resi, waktu handover, status pengiriman |

Reservasi tidak boleh langsung mengurangi on-hand. `available_qty` dihitung sebagai
`on_hand - active_reserved`, sedangkan pengeluaran fisik baru mem-posting movement
saat picking/dispatch sesuai keputusan proses.

### 4.6 Lot, serial, kedaluwarsa, dan karantina

| Kebutuhan | Existing | Gap/aksi |
|---|---|---|
| Lot/batch | Dua versi `produk_batch` | Konsolidasikan ke batch tenant; definisikan unique `(produk_id, batch_no, supplier/manufacturer scope bila perlu)` |
| Serial number | Belum ditemukan | Tambah `produk_serial` dengan serial unique per tenant, batch opsional, status dan lokasi terakhir |
| Expiry/FEFO | Batch menyimpan expiry | Tambah received/manufactured date, QC status, blocked reason; index `(produk_id, expiry_date)` untuk lot aktif |
| Karantina | UI/stok telah mengenal karantina, struktur kanonis belum jelas | Modelkan sebagai location/status inventory yang eksplisit, bukan boolean lepas pada produk |
| Recall | Belum ada | Tambah `lot_recall`/status blokir dan audit seluruh movement terdampak |

### 4.7 Stock opname dan adjustment

Struktur tenant sudah dekat, tetapi perlu diperkuat:

- unique `nomor_dokumen` dalam tenant;
- scope gudang, zone, lokasi, kategori, atau produk yang eksplisit;
- `snapshot_at` dan `snapshot_ledger_id` supaya qty sistem tidak berubah selama
  proses hitung;
- blind count, count sequence, recount, assignee, verifier, dan approver;
- reason code selisih;
- unique detail sesuai scope opname;
- correlation ID ke movement adjustment;
- status pembatalan dan reversal setelah posting;
- larangan posting dua kali melalui unique idempotency constraint.

`sesi_stok_opname` dan `koperasi.stok_opname` diperlakukan sebagai sumber migrasi,
bukan ledger baru.

### 4.8 Replenishment dan procurement

`ambang_stok_gudang` baru menutup minimum threshold. Target perlu memiliki:

| Kolom/relasi tambahan | Alasan |
|---|---|
| `min_qty`, `max_qty`, `safety_stock` | Menentukan target replenishment, bukan hanya alarm |
| `lead_time_days`, `review_period_days` | Menghitung reorder point |
| `preferred_supplier_id` | Menghasilkan usulan pembelian |
| `source_gudang_id` | Menghasilkan usulan transfer internal |
| `uom_id` dan conversion snapshot | Kuantitas pengadaan konsisten |
| `metode` | MIN_MAX, REORDER_POINT, DAYS_OF_SUPPLY, MANUAL |
| `last_generated_at`/idempotency | Mencegah usulan ganda dari scheduler |

### 4.9 Valuasi dan akuntansi

Ledger stok tenant sudah menyimpan `harga_satuan` dan `nilai`, tetapi belum cukup
untuk audit costing FIFO/average yang lengkap.

Tabel logis yang diperlukan:

- `inventory_cost_layer`: layer masuk, remaining qty/value, sumber, batch, tanggal;
- `inventory_cost_consumption`: movement keluar mengambil layer mana dan berapa;
- `inventory_posting_link`: movement/cost event ke jurnal akuntansi;
- `inventory_period_close`: cutoff, status, approver, dan lock per periode.

Setiap nilai uang harus `numeric(18,2)`/`BigDecimal`. Existing entity dengan `Double`
harus dimigrasikan bertahap; jangan mengganti semua tipe dalam satu rilis tanpa
rekonsiliasi nilai historis.

## 5. Matriks tabel target dan keputusan reuse

Nama di bawah adalah **nama logis usulan**, belum final sampai keputusan Fase 0.

| Tabel target | Existing analog | Keputusan usulan |
|---|---|---|
| `gudang` | `{S}.gudang`, `sirs.gudang` | **Perluas tenant**, migrasikan/mapping legacy |
| `lokasi_stok` | `{S}.lokasi_stok`, `asset.lokasi` | **Perluas tenant**, gunakan asset location hanya sebagai referensi alamat/fisik |
| `produk_batch` | `{S}.produk_batch`, `koperasi.produk_batch` | **Konsolidasikan ke tenant** |
| `produk_serial` | Tidak ada | **Baru** |
| `mutasi_stok` | `{S}.mutasi_stok`, dua mutasi legacy | **Jadikan ledger kanonis dan perluas** |
| `saldo_stok` | `{S}.saldo_stok`, saldo mutable pada produk/batch | **Projection kanonis**, harus rebuildable |
| `reservasi_stok` | Tidak ada | **Baru** |
| `penerimaan_gudang*` | Pengadaan/retur/transfer | **Baru sebagai proses**, source docs lama tetap dipakai |
| `putaway_task*` | Tidak ada | **Baru** |
| `transfer_gudang*` | `asset.pengiriman_gudang*`, `mutasi_stok_toko` | **Adaptasi/migrasi bertahap** |
| `picking_*`, `packing*`, `shipment*` | Tidak ada | **Baru** |
| `stok_opname*` | Tenant + legacy opname | **Perluas tenant**, migrasikan legacy |
| `reorder_rule` | `ambang_stok_gudang` | **Perluas/migrasikan** |
| `inventory_cost_*` | harga/nilai movement dan batch | **Baru** |
| `inventory_posting_link` | Posting akuntansi tersebar | **Baru** |

## 6. Gap kolom lintas tabel

Kolom berikut harus distandardisasi pada semua dokumen WMS:

| Kelompok | Kolom/kontrak |
|---|---|
| Tenant dan organisasi | tenant/schema implicit, `toko_id`, `gudang_id`, `lokasi_stok_id` |
| Identitas dokumen | `nomor_dokumen`, `source_type`, `source_id`, `source_line_id` |
| Waktu | `waktu_transaksi`, `dibuat_pada`, `tanggal_dirubah`, `diposting_pada`, timezone policy |
| Aktor | `dibuat_oleh_id`, `dilaksanakan_oleh_id`, `disetujui_oleh_id`, `device_id` |
| Presisi | qty `numeric(18,4)`, uang `numeric(18,2)`, conversion factor dengan skala memadai |
| Integritas retry | `idempotency_key` unique, `correlation_id`, request/source fingerprint |
| Workflow | `status`, `version`, reason code, approval/rejection notes |
| Audit koreksi | `reversal_of_id`, `cancelled_at/by`, immutable posting |
| Migrasi | `legacy_source`, `legacy_id` atau mapping table; row hash bila diperlukan |

## 7. Gap constraint dan index

### 7.1 Constraint yang harus ditambahkan

- unique kode gudang dalam scope tenant; tentukan apakah scope juga per toko;
- unique `(gudang_id, kode)` dan barcode lokasi;
- larangan parent lokasi menunjuk dirinya sendiri serta deteksi cycle di service;
- unique batch scoped sesuai kebijakan bisnis;
- unique serial number dalam tenant;
- unique partial `mutasi_stok.idempotency_key WHERE idempotency_key IS NOT NULL`;
- check `arah IN (-1, 1)` dan kuantitas non-negatif;
- unique normalized dimension pada `saldo_stok` termasuk penanganan nilai `NULL`;
- unique nomor dokumen opname/transfer/receipt;
- unique source posting agar satu source line/event tidak diposting dua kali;
- foreign key ke gudang/lokasi/batch yang harus berada pada scope tenant yang sama,
  diverifikasi lewat service atau composite key bila dipilih.

### 7.2 Index minimum

- movement: `(produk_id, tanggal)`, `(gudang_id, lokasi_stok_id, produk_id)`,
  `(dokumen_tipe, dokumen_id)`, `correlation_id`, idempotency;
- saldo: normalized dimension key dan `(gudang_id, produk_id)`;
- batch: `(produk_id, expiry_date)` untuk batch aktif;
- reservation: `(produk_id, gudang_id, status, expires_at)`;
- task: `(status, assignee_id, priority, planned_at)`;
- dokumen: `(status, tanggal)`, nomor dokumen, source document;
- opname detail: `(stok_opname_id, lokasi_stok_id, produk_id, produk_batch_id)`;
- partial index untuk dokumen aktif/open agar daftar kerja tetap cepat.

Index akhir harus ditentukan dari `EXPLAIN (ANALYZE, BUFFERS)` dan volume nyata,
bukan sekadar menambahkan seluruh kombinasi kolom.

## 8. Strategi migrasi tanpa merusak fungsi lama

### Tahap A - baseline dan ownership

1. introspeksi schema produksi dan cocokkan dengan entity/migration;
2. inventarisasi semua jalur yang mengubah stok;
3. tetapkan ledger dan proyeksi saldo kanonis;
4. tentukan mapping tenant, toko, gudang, lokasi, produk, dan batch;
5. ambil baseline saldo/nilai per dimensi.

### Tahap B - extension kompatibel

1. tambah tabel/kolom nullable, constraint `NOT VALID` bila sesuai;
2. buat default gudang dan lokasi untuk data lama;
3. backfill mapping legacy secara batch dan dapat dilanjutkan;
4. jangan mengubah pembacaan UI lama terlebih dahulu.

### Tahap C - adapter dan shadow posting

1. source transaction tetap memakai logic lama;
2. adapter menghasilkan movement tenant dengan idempotency key;
3. movement shadow dibandingkan dengan saldo existing;
4. selisih masuk reconciliation queue, bukan dikoreksi diam-diam.

### Tahap D - cutover bertahap

1. aktifkan pembacaan proyeksi tenant per toko/feature flag;
2. validasi pengadaan, POS, retur, transfer, batch, dan opname;
3. hentikan dual-write hanya setelah seluruh jalur lulus;
4. tabel legacy tetap read-only selama masa rollback;
5. arsip/retire baru dilakukan setelah periode stabil yang disepakati.

## 9. Partitioning dan retensi

Tidak direkomendasikan membuat tabel per hari. Pola tersebut memperumit foreign key,
ORM, migration, query lintas tanggal, backup, dan `UNION ALL` dinamis.

Rekomendasi:

- master dan saldo tetap tabel biasa;
- movement menggunakan satu logical table;
- bila jumlah row dan hasil pengukuran membenarkan, gunakan native PostgreSQL range
  partition berdasarkan bulan pada `waktu_transaksi`/`tanggal`;
- otomatis buat partition sebelum bulan berjalan dan sediakan default partition;
- index lokal partition mengikuti query utama;
- retensi tidak boleh menghapus ledger yang masih dibutuhkan audit/akuntansi;
- data lama dapat dipindahkan ke tablespace/archive setelah closing dan checksum.

## 10. Query audit yang wajib dijalankan sebelum implementasi

Query final dibuat pada Fase 0, dengan keluaran minimal:

1. daftar tabel/kolom/tipe/nullability/default aktual;
2. seluruh PK, FK, unique, check constraint, dan index;
3. jumlah row dan ukuran tabel/index;
4. duplicate code, batch, document number, dan idempotency key;
5. orphan foreign key/logical reference;
6. null/negative/NaN/infinite qty dan nilai;
7. saldo produk/toko vs batch vs mutasi vs opname;
8. movement tanpa dokumen sumber dan dokumen tanpa movement;
9. data gudang/lokasi lintas tenant/toko yang tidak konsisten;
10. query plan untuk pencarian saldo, FEFO, ledger, dan daftar task.

## 11. Keputusan yang harus disetujui sebelum DDL dibuat

1. Apakah schema tenant menjadi target kanonis untuk seluruh instalasi atau hanya
   tenant eBisnis?
2. Apakah `sirs.gudang` dan `asset.lokasi` akan dimigrasikan penuh atau dipertahankan
   sebagai master referensi non-inventory?
3. Kapan stok dianggap keluar: saat allocation, picking, packing, atau dispatch?
4. Apakah negative stock dilarang per gudang/lokasi atau hanya diberi warning?
5. Metode costing yang dipakai per tenant/produk: moving average, FIFO, atau lainnya?
6. Scope unique batch dan serial number?
7. Apakah satu toko boleh memiliki banyak gudang dan satu gudang melayani banyak
   toko?
8. Retention dan partitioning ledger berdasarkan volume serta kebutuhan audit?
9. Siapa yang boleh approve adjustment, transfer, receipt rejection, dan reversal?
10. Bagaimana cutover dilakukan untuk Desktop, Android, JSP, dan ZK agar seluruh
    kanal memakai kontrak bisnis yang sama?

## 12. Definition of ready untuk desain schema rinci

Desain DDL rinci boleh dimulai setelah:

- hasil introspeksi production/staging tersedia;
- mapping semua tabel existing disetujui;
- ledger kanonis dan projection ownership disepakati;
- lifecycle dokumen utama disetujui;
- aturan UOM, batch, serial, reservation, negative stock, dan costing disepakati;
- baseline reconciliation memiliki angka yang dapat diulang;
- rollback/cutover per feature flag disetujui;
- tidak ada rencana membuat ledger atau saldo paralel baru.

## 13. Ringkasan gap prioritas

| Prioritas | Gap | Risiko bila tidak ditutup |
|---:|---|---|
| P0 | Ledger kanonis belum ditetapkan antara legacy dan tenant | Saldo ganda dan laporan berbeda |
| P0 | Idempotency movement belum unique | Retry menghasilkan stok ganda |
| P0 | Saldo projection belum memiliki unique dimension/watermark | Drift dan row saldo duplikat |
| P0 | Precision legacy masih `Double` | Selisih qty/nilai dan jurnal |
| P1 | Gudang/lokasi belum memiliki hirarki dan kebijakan bin | Putaway/picking tidak terkontrol |
| P1 | Receiving/QC/putaway belum dimodelkan | Pengadaan dianggap langsung tersedia |
| P1 | Reservation/picking belum ada | Overselling dan fulfillment tidak dapat diaudit |
| P1 | Opname belum memiliki snapshot/recount/idempotent posting | Selisih berubah saat proses dan adjustment ganda |
| P2 | Serial, recall, replenishment, dan cost layer belum lengkap | Traceability dan valuasi terbatas |

Kesimpulan akhirnya: struktur tenant V2/V3 sudah merupakan fondasi terbaik, tetapi
harus diperkuat dan diintegrasikan dengan alur lama. Implementasi yang aman adalah
**konsolidasi bertahap**, bukan penggantian sekaligus dan bukan penambahan sistem stok
baru yang berdiri sendiri.
