# Implementasi Fase 2 — Master Identitas Item, UOM, dan Lokasi

Tanggal: 25 Agustus 2026  
Status: desain fisik dan preflight siap; DDL produksi belum dieksekusi

## 1. Tujuan fase

Fase ini membangun bahasa data yang sama untuk Pengadaan, Pergudangan,
Distribusi, Produksi, dan POS tanpa merusak fungsi lama. Hasil akhirnya setiap
baris dokumen dapat menunjuk secara tidak ambigu kepada:

1. item yang dimaksud;
2. satuan transaksi dan satuan dasar;
3. lokasi bisnis, gudang, serta bin bila relevan;
4. sumber data legacy yang tetap dapat ditelusuri.

Fase ini bersifat additive. Writer legacy tetap hidup sampai rekonsiliasi dan
cutover masing-masing domain dinyatakan lulus.

## 2. Temuan model existing

### 2.1 Tiga dunia identitas item

| Domain | Entity/table existing | Peran yang dipertahankan |
|---|---|---|
| POS/retail | `ais.database.model.inventory.Produk` / `koperasi.produk` | SKU toko, barcode, harga, stok operasional, batch/expiry, dan relasi ke toko |
| Aset/pengadaan | `ais.database.model.asset.MasterAsset` / `asset.master_asset` | master barang/aset untuk PR, PO, dan BAST existing beserta akun dan atribut aset |
| Medis/SIRS | item dan satuan SIRS, termasuk `sirs.satuan_item` | katalog serta satuan yang dipakai domain medis |

Ketiganya tidak boleh digabung dengan menyamakan primary key. Satu barang bisnis
dapat memiliki representasi berbeda karena scope, lifecycle, dan kebutuhan audit
yang berbeda.

### 2.2 Lokasi

| Entity/table existing | Keputusan |
|---|---|
| `koperasi.toko` | tetap menjadi business location/outlet |
| `sirs.gudang` | tetap menjadi master gudang; diperluas dengan scope lokasi dan atribut WMS |
| `koperasi.toko.gudang_pemasok` | dipertahankan sebagai konfigurasi sumber default, bukan satu-satunya relasi outlet–gudang |

### 2.3 UOM

`koperasi.satuan_produk`, `sirs.satuan_item`, dan atribut satuan pada
`asset.master_asset` tetap dapat dibaca. Konversi lintas domain tidak boleh memakai
`double precision`; faktor canonical disimpan sebagai numerator/denominator
`numeric(18,6)` agar dapat dibalik dan diaudit.

## 3. Desain fisik additive

Schema target disarankan `supply_chain`. Nama schema memisahkan agregat rantai
pasok dari tabel legacy tanpa membuat database/aplikasi baru.

### 3.1 `canonical_item`

| Kolom | Tipe | Aturan |
|---|---|---|
| `id` | `bigserial` | primary key internal |
| `tenant_key` | `varchar(100)` | wajib, normalisasi tenant |
| `item_code` | `varchar(100)` | wajib, kode bisnis stabil |
| `item_name` | `varchar(500)` | wajib |
| `item_kind` | `varchar(30)` | `PRODUCT`, `RAW_MATERIAL`, `SEMI_FINISHED`, `FINISHED_GOOD`, `ASSET`, `SERVICE`, `MEDICAL` |
| `base_uom_code` | `varchar(50)` | kode UOM canonical |
| `track_lot`, `track_serial`, `track_expiry` | `boolean` | default `false` |
| `active` | `boolean` | default `true` |
| `version_no` | `bigint` | optimistic locking |
| audit | timestamp/user | wajib |

Unique: `(tenant_key, item_code)`.

### 3.2 `canonical_item_legacy_map`

| Kolom | Aturan |
|---|---|
| `canonical_item_id` | FK ke `canonical_item` |
| `source_type` | `KOPERASI_PRODUK`, `ASSET_MASTER_ASSET`, `SIRS_ITEM` |
| `source_id` | ID legacy sebagai `bigint` |
| `source_scope_id` | toko/unit bila identitas legacy bersifat lokal |
| `is_primary` | satu sumber utama per tipe/scope |
| audit | siapa/kapan mapping dibuat |

Unique: `(source_type, source_id)` dan partial unique sumber utama per
`canonical_item_id, source_type, source_scope_id`.

Bridge ini adalah satu-satunya tempat penyamaan identitas. Kolom FK langsung yang
sudah ada, misalnya `produk.master_asset`, tetap dipertahankan sebagai adapter
selama masa transisi.

### 3.3 `canonical_uom` dan `item_uom_conversion`

`canonical_uom` memiliki `tenant_key`, `uom_code`, `uom_name`, `dimension`, dan
precision. `item_uom_conversion` minimal memuat:

- item;
- from/to UOM;
- numerator dan denominator positif;
- rounding scale/mode;
- effective start/end;
- version dan audit.

Unique aktif pada `(item, from_uom, to_uom, effective_from)`. Konversi identitas
1:1 tidak perlu disimpan. Konversi bolak-balik harus menghasilkan nilai semula
dalam toleransi precision yang ditetapkan.

### 3.4 `business_location`, extension gudang, zona, dan bin

`business_location` adalah registry bridge, bukan pengganti `koperasi.toko`.

| Target | Fungsi |
|---|---|
| `business_location` | tenant, kode, nama, tipe lokasi, timezone, source type/id |
| extension `sirs.gudang` atau `warehouse_extension` | relasi ke business location, tipe/capability gudang, aktif |
| `warehouse_zone` | receiving, storage, quarantine, production, staging, dispatch |
| `warehouse_bin` | alamat stok terkecil, unique per gudang, capacity/restriction |
| `location_warehouse_assignment` | banyak gudang sumber/tujuan per outlet dengan priority dan tanggal efektif |

Unique minimum:

- business location: `(tenant_key, location_code)`;
- gudang: `(tenant_key, warehouse_code)` setelah data global existing dipetakan;
- zone: `(warehouse_id, zone_code)`;
- bin: `(warehouse_id, bin_code)`;
- assignment aktif: `(location_id, warehouse_id, assignment_type, effective_from)`.

## 4. Resolver kompatibilitas

Resolver server harus menerima discriminator dan ID legacy, lalu mengembalikan
canonical item. Urutan resolusi:

1. lookup `canonical_item_legacy_map`;
2. bila belum ada, gunakan relasi eksplisit existing (contoh
   `koperasi.produk.master_asset`);
3. bila kandidat tepat satu, buat mapping dalam transaksi terkontrol;
4. bila nol atau lebih dari satu kandidat, tandai untuk rekonsiliasi manual—jangan
   memilih berdasarkan nama saja.

Nama produk hanya sinyal pencarian, bukan kunci integritas. Barcode/kode yang
kosong tidak boleh dipaksa menjadi string kosong pada unique key; normalkan ke
`NULL`.

## 5. Tahapan implementasi coding

### 5.1 Fase 2A — preflight (sekarang)

- jalankan SQL preflight pada salinan database;
- simpan hasil row count, duplikasi, orphan, dan kandidat ambigu;
- tetapkan `tenant_key` dan scope kode per instalasi;
- tentukan toleransi konversi UOM;
- jangan menambah constraint sebelum data merah diselesaikan.

### 5.2 Fase 2B — schema additive

- buat schema/tabel bridge;
- tambahkan index dan constraint `NOT VALID` terlebih dahulu untuk FK besar;
- buat model Hibernate Java 1.7 pada kedua source tree;
- seluruh `openSession()`/`currentNativeSession()` wajib ditutup di `finally`;
- current session tidak ditutup manual.

### 5.3 Fase 2C — backfill idempotent

- backfill per tenant/toko dalam batch kecil;
- checkpoint terakhir disimpan;
- gunakan unique key agar rerun tidak menggandakan data;
- mapping ambigu masuk tabel antrean rekonsiliasi, bukan ditebak otomatis;
- catat checksum sebelum/sesudah.

### 5.4 Fase 2D — read adapter

- PR/PO/BAST, Produk, Pergudangan, dan POS membaca label item/location melalui
  resolver;
- writer lama belum diubah;
- ukur latency dan cache hit; lookup harus terindeks.

### 5.5 Fase 2E — dual reference terkontrol

- dokumen baru menyimpan reference legacy dan canonical;
- validasi keduanya menunjuk barang yang sama;
- mismatch menolak posting, bukan sekadar warning;
- audit correlation/idempotency tetap aktif.

## 6. UAT dan gerbang kelulusan

Fase 2 dinyatakan lulus hanya bila:

1. 100% baris target PR/PO/BAST/stock request/transfer mempunyai tepat satu item
   canonical atau tercatat eksplisit sebagai service/cost;
2. tidak ada mapping `(source_type, source_id)` ganda;
3. konversi UOM round-trip lulus pada seluruh sample precision;
4. tidak ada gudang, zone, atau bin ganda dalam scope yang sama;
5. kode, akun, harga, HPP, resep, dan stok legacy tidak berubah akibat backfill;
6. rollback feature flag mengembalikan pembacaan legacy tanpa kehilangan data;
7. Desktop, Android, JSP, dan ZKoss menampilkan label item/lokasi yang sama.

## 7. Keputusan untuk fase berikutnya

Setelah gerbang Fase 2 lulus, Fase 3 membuat `stock_request` dan replenishment.
Permintaan stok outlet tidak diubah menjadi PR sebelum allocation membuktikan stok
internal tidak mencukupi. Ini mencegah pengadaan vendor ganda dan menjaga pemisahan
tanggung jawab Gudang dengan Pengadaan.

