# Gap analisis ulang dokumen Inventory

Tanggal analisis: 27 Agustus 2026  
Sumber: `C:\Users\Admin1\Downloads\Inventory (1).pdf`  
Jumlah halaman yang ditinjau: 11 halaman

## 1. Tujuan

Dokumen ini menilai ulang isi `Inventory (1).pdf` sebagai referensi untuk modul Inventory/Pergudangan eBisnis. Penilaian dilakukan dengan membandingkan kebutuhan yang tampak pada setiap halaman PDF terhadap rancangan terpadu, gap schema, blueprint menu, dan fase implementasi yang sudah tersedia di `/docs/pos`.

Analisis ini membedakan tiga hal:

1. fitur yang memang terlihat dalam PDF;
2. kebutuhan yang telah tercakup dalam blueprint existing;
3. gap yang masih harus didefinisikan sebelum coding atau UAT dapat dianggap lengkap.

## 2. Kesimpulan eksekutif

PDF berguna sebagai **referensi visual dan katalog fitur tingkat tinggi**, tetapi belum merupakan spesifikasi fungsional maupun teknis yang siap diimplementasikan.

Kekuatan dokumen:

- memperlihatkan dashboard inventory, penerimaan, pengiriman, transfer, adjustment, scrap, replenishment, produk, varian, rute beli/produksi, konfigurasi akuntansi, dan laporan;
- memberi gambaran interaksi pengguna seperti membuka detail, melakukan validasi, dan melihat status;
- menunjukkan bahwa inventory harus terhubung ke penerimaan, pengiriman, POS, manufaktur, pembelian, dan akuntansi.

Kelemahan utamanya:

- tidak menetapkan **sumber kebenaran stok**;
- tidak mendefinisikan struktur gudang, lokasi, bin, lot, serial, dan satuan;
- tidak mendefinisikan status serta transisi dokumen secara konsisten;
- tidak menjelaskan kapan stok, nilai persediaan, jurnal, utang, dan pembayaran berubah;
- tidak memetakan kebutuhan ke tabel dan modul existing eBisnis;
- tidak mencakup alur pengecualian, konkurensi, idempotensi, offline, keamanan, performa, migrasi, dan kriteria penerimaan.

Dengan demikian, PDF sebaiknya diperlakukan sebagai **input UX dan daftar kapabilitas**, sedangkan sumber rancangan implementasi tetap blueprint terpadu eBisnis. Coding tidak boleh menyalin tampilan PDF tanpa terlebih dahulu mengunci kontrak data, state machine, ownership, dan aturan rekonsiliasi.

## 3. Penilaian per halaman

| Halaman | Isi yang terlihat | Nilai bagi rancangan | Gap yang belum dijelaskan | Prioritas |
|---|---|---|---|---|
| 1 | Dashboard inventory dan widget penerimaan/pengiriman/POS/manufaktur | Menegaskan kebutuhan control tower lintas modul | Definisi KPI, periode, tenant/toko/gudang, sumber query, refresh, drill-down, dan kondisi kosong/error | P1 |
| 2 | Detail referensi dan status `draft/siap/selesai`, tombol validasi | Menunjukkan perlunya lifecycle dokumen | Aktor, syarat transisi, approval versus eksekusi, rollback, pembatalan, audit, dan efek validasi terhadap stok/jurnal | P0 |
| 3 | Stok gudang, forecast inventory, RFQ/PR, penawaran/PO, pending, serta stok pengiriman | Mengarah ke perencanaan dan replenishment | Formula forecast, lead time, safety stock, reservation, on-order, in-transit, backorder, dan definisi pending | P0 |
| 4 | Detail pengiriman, status persetujuan, informasi tambahan | Mengarah ke outbound/shipment | Allocation, picking, packing, load, dispatch, proof of delivery, penerimaan outlet, short/over/damage, dan retur | P0 |
| 5 | Transfer, adjustment, pengadaan/replenishment, daftar penerimaan | Menegaskan jenis operasi inventory | Dokumen kanonik, nomor referensi, source/destination, alasan, approval, dan larangan perubahan stok langsung | P0 |
| 6 | Physical adjustment dan scrap | Menunjukkan kontrol selisih fisik dan barang dibuang | Cycle count, blind count, toleransi, bukti, karantina, disposition, jurnal kerugian, dan segregasi tugas | P0 |
| 7 | Replenishment dan menu produk/varian/serial | Menunjukkan kebutuhan master item | SKU, UOM, conversion, barcode, lot/serial, expiry, FEFO, batch attributes, dan aturan varian | P0 |
| 8 | Informasi umum produk serta atribut dan varian | Menjadi referensi UI master produk | Data dictionary, uniqueness, produk-vs-master-asset, variant matrix, inactive/merge, dan histori perubahan | P1 |
| 9 | Produk tersedia di POS serta vendor/cost/lead time pembelian | Menegaskan integrasi sales dan purchasing | Multi-vendor, MOQ, price break, currency, tax, validity, preferred vendor, substitusi, dan harga pokok | P1 |
| 10 | Rute `Buy` atau `Produce`, data logistik, akun akuntansi | Menegaskan integrasi procurement, produksi, dan GL | Route policy multi-sumber, BOM, yield, WIP, landed cost, valuation method, account mapping, dan posting event | P0 |
| 11 | Laporan stok, histori pergerakan, dan analisis pergerakan | Menegaskan kebutuhan reporting | Definisi saldo awal/masuk/keluar/akhir, cutoff, UOM, valuasi, reconciliation, export, paging, dan audit drill-down | P0 |

## 4. Gap analisis yang paling kritis

### 4.1 Tidak ada model stok kanonik

PDF menggunakan istilah stok gudang, stok pengiriman, forecast, dan pending tanpa mendefinisikan komponen saldo. Implementasi harus membedakan sekurang-kurangnya:

- `on_hand`: stok fisik yang tercatat;
- `reserved`: stok yang sudah dialokasikan untuk order/transfer/produksi;
- `available`: `on_hand - reserved - quarantine`;
- `quarantine`: stok menunggu QC atau keputusan;
- `damaged`: stok rusak yang belum didisposisi;
- `in_transit`: stok telah keluar dari sumber tetapi belum diterima tujuan;
- `on_order`: stok yang dipesan ke vendor tetapi belum diterima;
- `wip`: bahan yang sudah dikonsumsi dan masih dalam proses produksi.

Tanpa definisi ini, widget, forecast, replenishment, dan laporan dapat menghasilkan angka yang berbeda walaupun membaca transaksi yang sama.

### 4.2 Tidak ada immutable inventory ledger

Semua perubahan stok harus menghasilkan event ledger yang tidak diubah diam-diam. Saldo boleh disimpan sebagai read model untuk performa, tetapi harus dapat direkonsiliasi kembali ke ledger.

Minimal event yang diperlukan:

- receipt vendor;
- putaway;
- transfer keluar/masuk;
- reservation/release;
- pick/pack/ship;
- receipt outlet;
- adjustment plus/minus;
- quarantine/release;
- scrap;
- consumption/production output;
- sale/return;
- stock opname correction.

Setiap event harus membawa `source_type`, `source_id`, `source_line_id`, toko, gudang, lokasi asal/tujuan, item, UOM, qty, lot/serial, waktu efektif, pengguna, perangkat, alasan, dan idempotency key.

### 4.3 State machine belum didefinisikan

PDF memakai beberapa status yang tampak tidak konsisten: `draft`, `siap`, `selesai`, `menunggu`, dan status persetujuan. Approval tidak boleh disamakan dengan status eksekusi.

Contoh pemisahan minimum:

- status dokumen: `DRAFT`, `SUBMITTED`, `APPROVED`, `REJECTED`, `CANCELLED`;
- status fulfillment: `UNALLOCATED`, `ALLOCATED`, `PICKED`, `PACKED`, `SHIPPED`, `PARTIALLY_RECEIVED`, `RECEIVED`, `CLOSED`;
- status QC: `NOT_REQUIRED`, `PENDING`, `PASSED`, `FAILED`, `QUARANTINED`;
- status posting: `UNPOSTED`, `POSTED`, `REVERSED`.

Untuk setiap transisi harus ditetapkan role, precondition, perubahan data, event stok, event jurnal, notifikasi, dan mekanisme reversal.

### 4.4 Struktur gudang dan lokasi belum ada

Istilah "gudang" pada PDF belum menjawab:

- satu toko boleh mempunyai berapa gudang;
- apakah gudang memiliki zone, aisle, rack, bin, receiving bay, staging, quarantine, dan scrap area;
- apakah stok dimiliki tenant, toko, divisi, consignment owner, atau vendor;
- bagaimana default location dan putaway rule ditentukan;
- bagaimana perpindahan internal dicatat tanpa dianggap pengiriman antar-outlet.

Blueprint harus mengunci hierarki `tenant -> toko/unit -> gudang -> lokasi/bin` serta constraint agar stok tidak lintas tenant atau toko secara tidak sah.

### 4.5 Lot, serial, batch, kedaluwarsa, dan FEFO belum memadai

Walaupun menu serial terlihat, PDF belum mendefinisikan lifecycle batch. Untuk minimarket, apotik, bahan baku, dan produksi, sistem perlu:

- lot/batch supplier dan lot internal;
- serial number bila wajib;
- manufacture date dan expiry date;
- batch status dan QC status;
- FEFO untuk allocation/picking;
- recall dan traceability dari vendor hingga outlet/POS;
- split/merge lot saat repack atau produksi;
- larangan penjualan batch karantina/kedaluwarsa.

### 4.6 Inbound belum end-to-end

Daftar penerimaan pada PDF belum menjelaskan hubungan dengan PR, PO, BAST, tagihan, dan pembayaran existing.

Alur target harus membedakan:

1. expected receipt dari PO/transfer/return;
2. physical unloading;
3. quantity check;
4. quality check;
5. discrepancy/claim;
6. BAST/receipt confirmation;
7. putaway;
8. invoice matching;
9. posting AP dan inventory valuation.

Penerimaan parsial, kelebihan, kekurangan, salah barang, rusak, dan barang tanpa PO harus mempunyai decision table tersendiri.

### 4.7 Outbound dan distribusi belum end-to-end

PDF belum membedakan permintaan stok outlet, alokasi gudang, delivery order, freight order, shipment, dan penerimaan outlet.

Alur target:

`Permintaan outlet -> approval -> allocation -> wave/picking -> packing -> DO -> shipment -> in-transit -> penerimaan outlet -> discrepancy/retur -> close`.

Harus ditentukan pula apakah barang in-transit masih milik gudang pusat, telah menjadi milik outlet, atau berada pada virtual transit location.

### 4.8 Forecast dan replenishment tidak mempunyai rumus

Tampilan forecast belum cukup untuk implementasi. Minimal harus ditentukan:

- reorder point;
- minimum/maximum stock;
- safety stock;
- average daily usage;
- supplier/internal lead time;
- demand horizon;
- seasonality dan promo;
- open PR/PO/transfer;
- reservation dan backorder;
- MOQ, pack size, UOM conversion;
- aturan pembulatan serta substitusi.

Sistem juga harus menjelaskan apakah saran replenishment otomatis membuat draft permintaan outlet, PR, atau transfer request.

### 4.9 Adjustment dan scrap berisiko menjadi jalan pintas

Fitur adjustment/scrap tidak boleh langsung memperbarui saldo tanpa ledger, reason code, approval, dan audit. Harus ada:

- batas toleransi per role;
- mandatory reason dan evidence;
- dual control untuk nilai besar;
- lokasi asal dan disposition;
- jurnal selisih persediaan atau kerugian;
- reversal, bukan delete;
- laporan adjustment dan scrap per pengguna/lokasi/alasan.

### 4.10 Produksi belum cukup terdefinisi

Pilihan `Produce` pada produk belum menjelaskan:

- BOM dan versinya;
- issue bahan baku;
- substitusi bahan;
- batch produksi;
- yield, shrinkage, waste, by-product;
- WIP;
- QC hasil;
- expiry hasil;
- biaya tenaga kerja/overhead;
- konversi barang setengah jadi menjadi barang jadi siap POS.

### 4.11 Valuasi dan akuntansi belum ditetapkan

Tab Accounting hanya menunjukkan kebutuhan mapping akun. Spesifikasi harus mengunci:

- metode valuasi: moving average/FIFO/standard cost;
- kapan COGS dihitung;
- kapan inventory asset berubah;
- landed cost, freight, duty, diskon, pajak, dan selisih kurs;
- accrual goods received not invoiced;
- three-way matching PO-receipt-invoice;
- retur dan reversal;
- mapping akun per kategori, gudang, atau unit;
- rekonsiliasi inventory subledger ke general ledger.

### 4.12 Hak akses dan segregasi tugas tidak disebutkan

Setiap menu dan aksi perlu didaftarkan pada registry dan `TbmroleAction`. `Common.apakahAdmin() == true` boleh melihat seluruh menu, tetapi operasi berisiko tetap harus tercatat dalam audit.

Aksi granular minimum:

- view, create, edit draft, submit, approve, reject, validate;
- allocate, pick, pack, ship, receive, QC, putaway;
- adjust, scrap, release quarantine;
- cancel, reverse, post, export;
- melihat cost, margin, dan akun akuntansi.

### 4.13 Konkurensi, idempotensi, dan offline tidak dibahas

Pada banyak kasir/outlet, transaksi dapat dikirim ulang atau stok dapat dialokasikan bersamaan. Diperlukan:

- idempotency key per command/event;
- optimistic locking/version;
- unique constraint untuk source document line;
- transaksi database yang atomic;
- retry aman;
- outbox/inbox untuk sinkronisasi;
- aturan konflik local-first;
- status sinkronisasi dan asal mesin/kasir;
- deduplikasi lintas perangkat dalam toko yang sama.

### 4.14 Performa dan skala belum dibahas

Untuk puluhan ribu produk dan ratusan ribu transaksi, UI tidak boleh memuat seluruh produk, transaksi, atau movement saat halaman dibuka. Minimum:

- server-side search dan paging;
- lazy loading;
- index untuk tenant/toko/gudang/item/waktu/status/source;
- read model/dashboard terpisah;
- batch command untuk posting besar;
- batas export serta background job;
- monitoring slow query, connection pool, dan idle-in-transaction;
- retention/archive tanpa membuat tabel harian dinamis.

Tabel transaksi per tanggal seperti `transaksi_DD_MM_YYYY` tidak disarankan. Gunakan satu model kanonik dengan partitioning database berdasarkan tanggal bila volume benar-benar memerlukan, sehingga query lintas periode tidak bergantung pada `UNION ALL` dinamis.

### 4.15 Laporan belum memiliki kontrak rekonsiliasi

Setiap angka pada laporan harus dapat ditelusuri sampai ledger event dan dokumen sumber. Definisi minimum:

- timezone dan cutoff;
- tanggal dokumen vs tanggal efektif vs tanggal posting;
- UOM dasar dan conversion;
- quantity serta value opening/in/out/closing;
- termasuk/tidak termasuk reserved, quarantine, in-transit, WIP;
- metode valuasi;
- pembulatan;
- transaksi cancelled/reversed;
- tenant/toko/gudang/location filter;
- total footer dan drill-down.

## 5. Gap terhadap tabel dan modul existing eBisnis

### 5.1 Modul existing yang harus digunakan kembali

| Kebutuhan | Existing | Keputusan |
|---|---|---|
| PR | `PermintaanPengadaanMasterAsset` dan detail | Pertahankan sebagai dokumen procurement; tambahkan extension/bridge, jangan duplikasi PR |
| PO | `PemesananPengadaanMasterAsset` dan detail | Pertahankan; beri atribut termin/nontermin dan fulfillment melalui extension bila belum tersedia |
| BAST/vendor receipt | `PenerimaanPengadaanMasterAsset` dan detail | Pertahankan sebagai bukti penerimaan bisnis; event WMS dan ledger dibuat melalui bridge yang idempotent |
| Terima tagihan | `SaldoAwalMasterAsset` dan detail | Dapat dipertahankan sementara, tetapi nama dan semantiknya tidak ideal; wajib adapter dan target refactor AP |
| Pembayaran | `ProsesTransfer` dan `DaftarPengajuanTransfer` | Pertahankan sebagai workflow pembayaran; hubungkan ke invoice/AP, jangan menjadi sumber stok |
| Produk/kategori/grup | Modul Produk, Jenis Produk, Grup Produk | Pertahankan sebagai master; tambahkan identitas SKU/UOM/variant/lot melalui extension yang jelas |
| Pengadaan ringan | Kulakan | Pertahankan untuk pembelian operasional sesuai scope; jangan dijadikan duplikat PO enterprise |
| Koreksi fisik | Stok Opname | Pertahankan UI/proses, tetapi posting melalui ledger adjustment |
| Expiry | Kedaluwarsa | Pertahankan UI; sumber datanya harus batch/lot expiry kanonik |
| Transfer | Mutasi Antar Outlet | Pertahankan sebagai entry point; fulfillment dilakukan oleh WMS outbound/inbound dan shipment |

### 5.2 Tabel/konsep baru atau extension yang tetap diperlukan

- registry item/SKU dan UOM conversion;
- warehouse/location/bin;
- inventory ledger dan balance/read model;
- lot/serial/batch/QC/quarantine;
- reservation/allocation;
- replenishment policy dan proposal;
- inbound receipt/putaway bridge;
- outbound pick/pack/ship;
- delivery order, shipment, freight, proof of delivery;
- receipt outlet dan discrepancy;
- BOM, production order, consumption/output/waste;
- AP invoice matching dan posting bridge;
- outbox/inbox/idempotency registry;
- menu/action registry dan permission migration;
- reporting/read model/reconciliation snapshot.

### 5.3 Larangan desain

- jangan membuat PR/PO/BAST baru dengan arti yang sama;
- jangan menjadikan `SaldoAwalMasterAsset` sumber kebenaran inventory;
- jangan memperbarui stok langsung dari UI tanpa ledger event;
- jangan menggunakan status tunggal untuk approval, fulfillment, QC, dan posting;
- jangan menghapus movement yang sudah divalidasi; gunakan reversal;
- jangan mencampur `MasterAsset` dan `Produk` tanpa registry/bridge eksplisit;
- jangan menutup `currentSession()` secara manual;
- setiap `openSession()` atau `currentNativeSession()` harus ditutup di `finally` dengan `clear/disconnect/close` sesuai pola proyek;
- jangan menghasilkan `.class` di direktori sumber `.java`.

## 6. Gap pada dokumen analisis, bukan hanya gap fitur

PDF belum menyediakan artefak berikut:

1. daftar stakeholder dan RACI;
2. glossary istilah bisnis;
3. context diagram dan batas domain;
4. entity relationship diagram dan data dictionary;
5. cardinality, unique constraint, dan ownership;
6. state diagram per dokumen;
7. decision table untuk kasus parsial dan discrepancy;
8. kontrak API/event dan idempotency;
9. matriks role/action;
10. aturan jurnal dan rekonsiliasi;
11. NFR: performa, kapasitas, availability, security, retention;
12. migration/cutover/rollback;
13. observability dan audit trail;
14. acceptance criteria dan test scenario;
15. definisi KPI/report;
16. parity Desktop, Android, JSP, dan ZKoss.

Tanpa artefak tersebut, dua tim dapat membuat layar yang mirip tetapi menghasilkan perilaku stok dan keuangan yang berbeda.

## 7. Tambahan yang harus dimasukkan ke spesifikasi Inventory berikutnya

### 7.1 Diagram wajib

- diagram konteks dari vendor sampai POS;
- lifecycle procurement dan inbound;
- lifecycle permintaan outlet dan outbound;
- lifecycle shipment dan penerimaan outlet;
- lifecycle produksi;
- lifecycle retur/reverse logistics;
- model lokasi dan ledger;
- sequence offline/retry/idempotency.

### 7.2 Decision table wajib

- penerimaan kurang/lebih/rusak/salah barang;
- penerimaan tanpa PO;
- partial receipt dan partial invoice;
- allocation kurang, backorder, dan substitusi;
- shipment hilang/rusak/terlambat;
- expiry, quarantine, release, scrap;
- selisih stock count;
- reversal setelah posting stok/jurnal;
- konflik sinkronisasi antarperangkat.

### 7.3 Kontrak UAT minimum

1. saldo awal + seluruh movement = saldo akhir untuk qty dan value;
2. satu command yang dikirim ulang tidak membuat movement ganda;
3. stok tidak dapat negatif kecuali policy eksplisit mengizinkan;
4. reserved tidak melebihi stok yang dapat dialokasikan;
5. batch expired/quarantine tidak dapat dijual atau dipick;
6. penerimaan parsial menjaga sisa outstanding dengan benar;
7. shipment parsial dan receipt parsial dapat direkonsiliasi;
8. three-way matching mendeteksi selisih qty/harga;
9. subledger inventory sama dengan GL setelah posting;
10. admin melihat seluruh menu dan role biasa hanya aksi `TbmroleAction`;
11. data volume besar tetap memakai paging/lazy load;
12. Desktop, Android, JSP, dan ZKoss menghasilkan aturan bisnis yang sama.

## 8. Prioritas penutupan gap

### P0 — Harus dikunci sebelum coding lanjutan

- canonical item/UOM/location/lot model;
- inventory ledger dan balance ownership;
- status/state machine terpisah;
- inbound/outbound/production posting rules;
- integration mapping ke PR/PO/BAST/invoice/payment existing;
- idempotency, concurrency, dan reversal;
- accounting/valuation rules;
- permission action dan audit;
- reconciliation contract.

### P1 — Dikerjakan bersama core flow

- replenishment formula;
- reservation, allocation, picking, packing;
- QC, quarantine, expiry, FEFO;
- shipment/POD/outlet discrepancy;
- report drill-down;
- server-side paging, indexing, dan observability;
- migration dan compatibility adapter.

### P2 — Setelah core flow stabil

- forecast lanjutan/seasonality;
- wave picking dan slotting;
- advanced landed-cost allocation;
- analytics produktivitas gudang;
- optimasi rute dan kapasitas pengiriman;
- rekomendasi otomatis berbasis histori.

## 9. Rekomendasi fase tindak lanjut

1. **Spec closure**: lengkapi data dictionary, state machine, decision table, RBAC, dan acceptance criteria.
2. **Fondasi data**: implementasikan item registry, UOM, warehouse/location, lot/serial, ledger, balance, reservation.
3. **Inbound**: hubungkan PO/BAST existing ke receiving, QC, discrepancy, dan putaway.
4. **Outbound**: hubungkan permintaan outlet ke allocation, pick/pack, DO, shipment, dan receipt outlet.
5. **Produksi**: BOM, consumption, WIP, output, waste, dan barang siap POS.
6. **AP dan Akuntansi**: matching, invoice, payment, valuation, COGS, dan reconciliation.
7. **Read model dan laporan**: dashboard, forecast, movement, valuation, drill-down, export.
8. **Parity dan rollout**: Desktop, Android, JSP, ZKoss, migration, load test, security test, dan rollback rehearsal.

Urutan ini selaras dengan blueprint yang sudah ada. PDF tidak memerlukan pembuatan modul tandingan; ia memperkuat kebutuhan agar fase WMS, replenishment, produk, produksi, laporan, dan akuntansi diselesaikan dengan kontrak yang konsisten.

## 10. Definition of Done untuk analisis Inventory

Analisis dianggap cukup untuk masuk ke coding apabila:

- seluruh istilah stok mempunyai definisi tunggal;
- setiap dokumen mempunyai state machine dan actor yang jelas;
- semua perubahan qty/value memetakan ke ledger dan jurnal;
- tabel existing yang direuse serta extension baru telah disetujui;
- alur normal, parsial, error, cancel, dan reversal terdokumentasi;
- RBAC/action registry lengkap;
- API/event/idempotency contract lengkap;
- KPI dan laporan dapat direkonsiliasi ke dokumen sumber;
- acceptance criteria per fase tersedia;
- migration, rollback, monitoring, dan load-test plan tersedia;
- tidak ada menu atau tabel duplikat dengan arti bisnis yang sama.

## 11. Keputusan akhir

Gap terpenting bukan kurangnya layar, melainkan belum adanya kontrak bisnis dan teknis yang menjamin bahwa seluruh layar membaca serta menulis sumber data yang sama. PDF dapat dipakai sebagai referensi tampilan, tetapi implementasi harus tetap mengikuti blueprint terpadu eBisnis, mempertahankan modul existing, dan menambahkan WMS/ledger/bridge hanya pada area yang memang belum dimiliki sistem.

## 12. Status implementasi per 28 Agustus 2026

Bagian ini membedakan kelengkapan **analisis** dari kelengkapan **implementasi**. Dokumen ini sudah mencakup gap utama Inventory secara menyeluruh, tetapi tidak berarti seluruh coding Inventory telah selesai.

### 12.1 Sudah tersedia

- audit terminologi, alur, tabel existing, integrasi, RBAC, akuntansi, offline, performa, migrasi, observability, dan UAT;
- blueprint menu terpadu tanpa membuat modul tandingan untuk fungsi existing;
- kebijakan bahwa pengguna dengan `Common.apakahAdmin() == true` dapat melihat seluruh menu aplikasi sebelum filter varian, role, atau action diterapkan;
- registry action `uom_konversi` pada blueprint menu server;
- menu **Satuan/UOM** pada aplikasi;
- CRUD katalog satuan produk melalui tabel existing `koperasi.satuan_produk`;
- pencarian, paging, status aktif, validasi nama duplikat, dan perlindungan penghapusan satuan yang masih dipakai produk;
- penutupan `openSession()` pada helper UOM melalui `finally` dengan `clear`, `disconnect`, dan `close`;
- pemeriksaan statis Flutter untuk routing/menu dan layar UOM tanpa temuan.

### 12.2 Belum selesai dan tetap menjadi gap implementasi

- matriks konversi antarsatuan, misalnya `1 dus = 24 pcs`, karena tabel existing `satuan_produk` baru menyimpan identitas satuan dan status aktif;
- aturan konversi yang memerlukan satuan asal, satuan tujuan, faktor, presisi, pembulatan, periode berlaku, dan audit perubahan;
- canonical item registry lengkap untuk bahan baku, barang setengah jadi, barang jadi, jasa, dan kemasan;
- warehouse/location/bin, lot/serial, inventory ledger, balance, reservation, dan valuation sebagai fondasi tunggal;
- state machine serta posting rule lengkap untuk inbound, outbound, produksi, retur, cancel, reversal, dan discrepancy;
- rekonsiliasi end-to-end PR/PO/BAST/tagihan/pembayaran dengan WMS, shipment, penerimaan outlet, produksi, dan POS;
- parity penuh aturan bisnis pada Desktop, Android, JSP, dan ZKoss;
- migration/cutover, load test, security test, observability, dan rollback rehearsal seluruh fase.

### 12.3 Kesimpulan status

- **Analisis gap Inventory:** sudah lengkap untuk menjadi peta implementasi.
- **Master Satuan/UOM dasar dan akses menu admin global:** sudah diimplementasikan.
- **Konversi UOM dan seluruh modul Inventory terpadu:** belum seluruhnya selesai dan harus mengikuti urutan P0, P1, lalu P2 pada dokumen ini.

Dengan demikian, jawaban atas pertanyaan “apakah sudah semua?” adalah: **sudah untuk cakupan analisis dan gap mapping, belum untuk seluruh implementasi coding Inventory**.
