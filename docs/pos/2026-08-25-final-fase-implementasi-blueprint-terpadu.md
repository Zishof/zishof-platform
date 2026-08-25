# Final fase implementasi blueprint terpadu eBisnis

Tanggal: 25 Agustus 2026  
Status: **roadmap final sebelum DDL dan coding implementasi**

Acuan utama:

- [Audit redundansi dan blueprint menu terpadu](2026-08-25-audit-redundansi-dan-blueprint-menu-terpadu.md)
- [Gap analysis tabel existing dan target terpadu](2026-08-25-gap-analisis-tabel-existing-dan-target-terpadu.md)
- [Rancangan terpadu Pengadaan, Pergudangan, Distribusi, Produksi, dan POS](2026-08-25-rancangan-terpadu-pengadaan-pergudangan-distribusi-produksi-pos.md)

## 1. Tujuan

Dokumen ini menyatukan seluruh analisis sebelumnya menjadi urutan implementasi final.
Ia menjadi peta kerja untuk schema, backend, Desktop, Android, JSP, ZKoss, migrasi,
UAT, deployment, observasi, dan penghentian writer legacy.

Dokumen ini belum menjalankan DDL atau mengubah proses produksi. Setiap fase harus
lulus gerbangnya sebelum fase yang bergantung kepadanya boleh menjadi writer utama.

## 2. Hasil akhir yang dituju

Alur bisnis target:

```text
Kebijakan stok / kebutuhan outlet
              |
              v
Permintaan stok outlet -- stok kurang --> konsolidasi kebutuhan --> PR --> PO
              |                                                |       |
              | stok tersedia                                  |       v
              v                                                |   BAST vendor
         Alokasi stok <-----------------------------------------+       |
              |                                                        v
              |                                              Receipt/QC/Putaway
              v                                                        |
     DO/Picking/Packing --> Shipment --> POD --> Penerimaan outlet     |
                                              |                        |
                                              +------------------------+
                                              v
                                      Produksi/Barang siap jual
                                              |
                                              v
                                             POS
                                              |
                                              v
                                    Ledger stok dan replenishment

PO + BAST vendor + Invoice --> 3-way match --> AP --> pembayaran --> jurnal
Seluruh event bisnis ----------> read model ----------> laporan/control tower
```

Prinsip tetap:

1. satu use case mempunyai satu pemilik kanonik;
2. satu kejadian stok menghasilkan satu movement dengan idempotency unik;
3. dokumen administratif, eksekusi fisik, pembayaran, dan jurnal dipisahkan;
4. tabel existing yang matang dipakai ulang melalui extension/adapter;
5. route dan izin legacy tidak langsung dihapus;
6. laporan tidak boleh memperbaiki transaksi sumber;
7. seluruh platform memakai kontrak API, menu key, action key, dan state machine
   yang sama;
8. `Common.apakahAdmin() == true` melihat seluruh menu, tetapi semua mutasi berisiko
   tetap melalui validasi domain dan audit.

## 3. Keputusan arsitektur yang dibekukan

### 3.1 Tabel existing yang dipertahankan

- PR: `PermintaanPengadaanMasterAsset` dan detail;
- PO: `PemesananPengadaanMasterAsset` dan detail;
- BAST vendor: `PenerimaanPengadaanMasterAsset` dan detail;
- eksekusi transfer/pembayaran: `ProsesTransfer` dan `DaftarPengajuanTransfer`;
- sumber role-action: `TbmroleAction`;
- master produk/toko/batch existing dipertahankan selama migrasi.

### 3.2 Tabel existing yang tidak boleh diperluas melampaui arti bisnisnya

- permintaan stok outlet tidak ditaruh sebagai PR;
- penerimaan outlet/POD tidak ditaruh sebagai BAST vendor;
- seluruh lifecycle shipment tidak dipaksakan ke `PengirimanGudang`;
- invoice AP baru tidak terus ditaruh sebagai `SaldoAwalMasterAsset`;
- saldo stok tidak boleh lagi diubah independen oleh banyak modul;
- `MasterAsset` dan `Produk` tidak digabung tanpa bridge identitas resmi.

### 3.3 Strategi tabel volume besar

Gunakan nama tabel stabil. Jangan membuat tabel harian seperti
`transaksi_DD_MM_YYYY`. Tambahkan index berdasarkan tenant, lokasi, status, dan
`business_at`. Partisi bulanan hanya diterapkan setelah benchmark membuktikan
kebutuhan dan seluruh query sudah memakai partition key.

## 4. Workstream dan dependensi

| Workstream | Pemilik hasil | Tidak boleh dimulai penuh sebelum |
|---|---|---|
| A. Registry dan hak akses | menu/action canonical | Fase 0 |
| B. Master dan identitas item | item, UOM, gudang, bin | A stabil |
| C. Inventory ledger | movement, balance, reservation | B stabil |
| D. Replenishment dan Pengadaan | stock request sampai PO | B dan C shadow |
| E. WMS | receipt sampai picking/packing | C dan D |
| F. Distribusi | transfer, DO, shipment, POD | E outbound |
| G. Produksi | BOM sampai output/waste | C dan master |
| H. AP dan Akuntansi | invoice, match, payment, posting | D dan E |
| I. Laporan dan Control Tower | read model | event/domain terkait stabil |
| J. Paritas platform | Desktop/Android/JSP/ZKoss | kontrak tiap domain stabil |

Pekerjaan UI shell boleh berjalan paralel setelah kontrak registry stabil. Writer
stok, AP, dan jurnal tidak boleh dikerjakan paralel sebagai implementasi independen.

## 5. Fase 0 — Baseline, governance, dan freeze kontrak

### Sasaran

Mendapatkan baseline produksi yang dapat direkonsiliasi serta mencegah perubahan
tanpa ownership selama implementasi.

### Pekerjaan

1. ekspor schema, constraint, index, ukuran tabel, row count, null ratio, orphan FK,
   dan duplicate business key;
2. inventaris semua menu, route, endpoint, controller, service, query, dan
   `TbmroleAction` pada Desktop, Android, JSP, ZKoss;
3. daftar seluruh writer stok, PR/PO/BAST, invoice, pembayaran, dan jurnal;
4. petakan transaksi database dan kepemilikan `openSession()`/`currentSession()`;
5. buat golden dataset dan hasil kontrol untuk:
   - direct purchase/Kulakan;
   - PR–PO–BAST;
   - mutasi antar outlet;
   - stok opname dan retur;
   - produksi bila sudah ada;
   - penjualan POS online/offline;
   - invoice, pembayaran, dan posting;
6. tetapkan konvensi ID, kode dokumen, timezone, currency precision, quantity
   precision, tenant scope, lokasi, idempotency, correlation, dan audit;
7. bekukan penambahan menu serta writer baru di luar registry dan domain owner.

### Artefak

- `menu-route-api-table-role-inventory.csv`;
- `mutation-writer-register.md`;
- query audit baseline;
- golden dataset beserta checksum;
- Architecture Decision Record untuk keputusan pada butir 6.

### Gerbang lulus

- seluruh menu dan endpoint mutasi mempunyai owner;
- nilai baseline dapat direproduksi;
- seluruh keputusan pada bagian 3 disetujui;
- backup dan prosedur restore diuji.

### Rollback

Tidak ada perubahan runtime; fase ini hanya inventarisasi dan freeze.

## 6. Fase 1 — Registry menu, action, alias, dan hak akses

### Perubahan data

1. tambah `app_menu_registry`;
2. tambah `app_action_registry`;
3. tambah `app_action_alias`;
4. gunakan `TbmroleAction` sebagai sumber izin dan tambah mapping canonical bila
   struktur existing belum dapat menyimpan action key langsung;
5. seed seluruh record secara idempoten.

### Backend

1. buat `menu_context` sebagai kontrak tunggal lintas platform;
2. buat resolver canonical action → legacy alias;
3. implementasikan admin override melalui helper resmi;
4. pisahkan izin `VIEW`, `CREATE`, `EDIT_DRAFT`, `SUBMIT`, `APPROVE`, `REJECT`,
   `CANCEL`, `POST`, `REVERSE`, `EXPORT`, `VIEW_COST`, dan `VIEW_ALL_LOCATION`;
5. audit seluruh aksi approve/post/reverse/admin override.

### UI

1. render menu dari registry pada Desktop dan Android;
2. sediakan adapter registry pada JSP dan ZKoss;
3. gunakan group collapsible sesuai blueprint;
4. route lama tetap berfungsi sebagai alias tanpa menampilkan menu ganda.

### UAT

- snapshot menu semantik identik pada empat platform;
- nol role kehilangan hak existing;
- non-admin tidak mendapat privilege baru;
- admin melihat semua menu;
- deep link route legacy tetap bekerja.

### Gerbang lulus

Tidak ada menu/action key tanpa registry dan tidak ada menu ganda pada sidebar.

### Rollback

Feature flag mengembalikan renderer menu existing; data registry tetap disimpan.

## 7. Fase 2 — Master data dan identitas item

### Perubahan data

1. tetapkan bridge `MasterAsset` ↔ `Produk` tanpa menyatukan primary key;
2. tambah `item_uom_conversion`;
3. lengkapi master gudang, zona, bin, dock, armada, ekspedisi, dan relasi toko-gudang;
4. tambahkan business key dan unique scope yang disepakati;
5. bersihkan duplikasi barcode, kode produk, gudang, dan lokasi.

### Backend dan UI

1. service lookup item canonical;
2. validasi konversi UOM dan pembulatan;
3. label `Jenis Produk` menjadi `Kategori Produk & Akun`;
4. label `Grup Produk` menjadi `Grup Harga, HPP & Resep`;
5. CRUD master konsisten pada semua platform;
6. admin dapat melihat lintas lokasi, sedangkan pengguna biasa tetap dibatasi scope.

### UAT

- lookup item yang sama menghasilkan identitas sama pada seluruh modul;
- konversi UOM dapat dibalik sesuai aturan precision;
- akun, harga, HPP, resep, dan stok existing tidak berubah;
- tidak ada lokasi/bin ganda pada scope yang sama.

### Gerbang lulus

Seluruh baris dokumen target dapat menunjuk item, UOM, gudang, dan lokasi secara
tidak ambigu.

### Rollback

Tabel baru bersifat additive; UI kembali ke master existing melalui feature flag.

## 8. Fase 3 — Inventory ledger, balance, lot, dan reservation

### Perubahan data

1. buat `inventory_movement` immutable;
2. buat `inventory_balance` sebagai proyeksi rebuildable;
3. buat `inventory_reservation`;
4. normalisasi referensi lot/batch/serial/expiry;
5. tambah unique `(source_type, source_id, event_type)` atau idempotency ekuivalen;
6. index item, warehouse, bin, lot, status, dan `business_at`.

### Backend

1. satu `InventoryPostingService` untuk receipt, transfer, sale, return, production,
   adjustment, dan reversal;
2. shadow-write ledger tanpa menjadikannya sumber saldo UI;
3. worker proyeksi balance yang dapat diulang;
4. reconciliation produk/batch/mutasi/opname dengan ledger;
5. larang hard delete movement; koreksi memakai reversal.

### Migrasi

1. backfill per periode dan lokasi;
2. simpan mapping legacy ID, target ID, checksum, batch, status/error;
3. rekonsiliasi opening + in − out = closing per item-lokasi-hari;
4. selesaikan exception sebelum cutover writer.

### UAT

- duplicate retry tidak membuat movement kedua;
- negative stock mengikuti konfigurasi resmi;
- rebuild balance menghasilkan angka identik;
- backdate dan reversal masuk periode yang benar;
- batch kedaluwarsa/karantina tidak available.

### Gerbang lulus

Shadow ledger sama dengan saldo existing pada toleransi nol atau exception yang telah
ditandatangani. Belum ada cutover global.

### Rollback

Writer existing tetap utama; shadow ledger dapat dibersihkan per migration batch.

## 9. Fase 4 — Perencanaan, replenishment, dan permintaan outlet

### Perubahan data

Tambah:

- `replenishment_policy`;
- `stock_request` dan `stock_request_line`;
- `demand_consolidation`;
- `replenishment_proposal`;
- `stock_allocation_plan`.

### Proses

1. outlet membuat permintaan berdasarkan kebutuhan manual atau min/max/reorder point;
2. gudang mengalokasikan stok yang tersedia;
3. shortage dikonsolidasi dan dapat membentuk PR existing;
4. pembelian lokal outlet menjadi exception berotorisasi, bukan jalur default;
5. perubahan demand, allocation, fulfilment, cancellation tercatat per line.

### UI

- Kebijakan Stok;
- Saran Pengadaan;
- Permintaan Stok Outlet;
- Konsolidasi Kebutuhan;
- Alokasi dan Backorder;
- antrian approval dan exception.

### UAT

- stok cukup tidak membuat PR;
- stok kurang hanya membuat satu demand procurement;
- partial allocation dan backorder benar;
- pembatalan melepaskan reservation;
- retry tidak menggandakan request atau PR.

### Gerbang lulus

Demand outlet dapat ditelusuri sampai allocation atau PR tanpa menulis stok langsung.

### Rollback

Matikan feature flag replenishment; dokumen draft baru tetap tersimpan read-only.

## 10. Fase 5 — Konsolidasi Pengadaan

### Perubahan data

1. buat `procurement_document_extension`;
2. buat `procurement_item_reference`;
3. tambah RFQ/quotation bila dipakai;
4. tambah PO delivery schedule dan payment term/milestone;
5. tambah status history dan legacy mapping;
6. termin/nontermin disimpan sebagai terms, bukan jenis PO paralel.

### Backend

1. PR, PO, dan BAST existing tetap header workflow kanonik;
2. Kulakan tetap direct purchase;
3. BAST-ke-Kulakan diganti adapter menuju receipt posting idempoten;
4. monitor barang belum datang dipisahkan dari konsep barang dalam proses;
5. retur pembelian membuat reversal inventory dan koreksi AP bila relevan.

### UAT

- PR → PO full/partial;
- PO langsung dengan alasan exception;
- termin dan nontermin;
- partial/over delivery dengan toleransi;
- satu BAST tidak dapat menambah stok dua kali;
- retur menurunkan stok dan liability yang benar.

### Gerbang lulus

Total PR, PO, receipt/BAST, dan commitment dapat direkonsiliasi per line.

### Rollback

Adapter kembali memanggil proses existing; extension tetap tidak merusak header lama.

## 11. Fase 6 — WMS inbound

### Perubahan data

Tambah receipt, receipt line, QC result, putaway task, lot/serial capture, dan exception
receipt.

### Proses

1. pre-receipt dari PO/BAST;
2. penerimaan fisik;
3. hitung kurang/lebih/rusak;
4. QC accept/reject/quarantine;
5. putaway ke bin;
6. inventory movement hanya saat transition yang disepakati;
7. dokumen administratif BAST tetap dibedakan dari aktivitas fisik WMS.

### UI

- Jadwal Kedatangan;
- Penerimaan Vendor;
- Pemeriksaan Mutu;
- Putaway;
- Anomali Penerimaan;
- antrean lot/expiry yang belum lengkap.

### UAT

- full, partial, short, over, damaged;
- item wajib batch/expiry;
- quarantine tidak masuk available stock;
- putaway parsial;
- scan ulang tidak menggandakan receipt/movement.

### Gerbang lulus

Setiap kuantitas diterima mempunyai lokasi, status mutu, source, dan movement yang
dapat ditelusuri.

### Rollback

Cutover per gudang; gudang pilot dapat kembali ke adapter existing setelah movement
pilot direverse secara terkontrol.

## 12. Fase 7 — Pengendalian persediaan WMS

### Perubahan data/proses

1. stock count session, assignment, count line, recount, approval;
2. adjustment reason dan approved posting;
3. transfer bin, replenishment internal, reservation, release;
4. FEFO/FIFO allocation;
5. quarantine, release, expiry, write-off;
6. audit movement dan rekonsiliasi saldo.

### UI

- Saldo per Lokasi;
- Kartu Stok;
- Batch/Serial/Kedaluwarsa;
- Stok Opname;
- Adjustment;
- Transfer Bin;
- Karantina;
- Rekonsiliasi.

### UAT

- blind count dan recount;
- concurrency dua petugas;
- adjustment hanya setelah approval;
- FEFO tidak mengambil batch karantina/kedaluwarsa;
- saldo proyeksi dapat direbuild.

### Gerbang lulus

Tidak ada edit langsung `produk.stok`; semua perubahan berasal dari movement resmi.

### Rollback

Writer dipindah per event type. Event yang belum cutover tetap memakai adapter lama.

## 13. Fase 8 — Outbound, distribusi, shipment, dan penerimaan outlet

### Perubahan data

Tambah:

- `stock_transfer` dan line;
- `delivery_order` dan line;
- `freight_order`;
- `shipment`, package, leg, dan event;
- `proof_of_delivery`;
- `outlet_receipt` dan line;
- claim, retur transfer, dan reverse logistics.

### Proses

1. allocation → wave/pick task;
2. picking → packing → staging;
3. DO dan shipment;
4. dispatch mengubah custody sesuai state machine;
5. POD membuktikan pengantaran;
6. penerimaan outlet mencatat qty diterima/kurang/rusak;
7. claim/retur/reverse logistics menutup selisih;
8. `PengirimanGudang` dan `MutasiStokToko` menjadi adapter legacy.

### UAT

- satu transfer banyak shipment;
- partial delivery dan split shipment;
- short/damaged/lost;
- POD tanpa/bersama penerimaan outlet;
- retry scan dan retry API idempoten;
- custody dan saldo in-transit benar.

### Gerbang lulus

Seluruh barang dari gudang sampai outlet dapat dilacak per dokumen, shipment, event,
POD, receipt, dan movement.

### Rollback

Pilot per rute/gudang/outlet; shipment baru dihentikan, shipment aktif diselesaikan
dengan writer versi yang membuatnya.

## 14. Fase 9 — Produksi dan barang siap jual

### Perubahan data

Tambah BOM/formula/version, production plan/order, material issue/return, WIP,
finished goods output, waste/yield, serta cost snapshot.

### Proses

1. formula terversi dan bertanggal efektif;
2. production order mereservasi bahan;
3. material issue membuat movement keluar;
4. return mengembalikan bahan tersisa;
5. output membuat finished goods movement;
6. waste/yield dan variance dicatat;
7. produk jadi tersedia untuk POS setelah quality/release yang diwajibkan.

### UAT

- standard vs actual usage;
- partial completion;
- substitute item terotorisasi;
- waste dan by-product;
- cost snapshot tidak berubah akibat edit formula di masa depan;
- rollback produksi memakai reversal.

### Gerbang lulus

Setiap barang jadi dapat ditelusuri ke production order, lot bahan, output, yield,
dan biaya.

### Rollback

Aktifkan per jenis produksi; item yang belum pilot tetap memakai proses existing.

## 15. Fase 10 — AP, tagihan, pembayaran, dan Akuntansi

### Perubahan data

1. buat `ap_invoice`, line, match result, dispute, payment schedule, credit note;
2. buat generic payment allocation yang menghubungkan eksekusi transfer ke invoice;
3. klasifikasi dan migrasikan penggunaan `SaldoAwalMasterAsset`;
4. buat posting source link, posting job, reversal, valuation layer, dan period lock.

### Proses

1. invoice masuk;
2. 2-way/3-way match ke PO dan receipt/BAST;
3. exception/dispute;
4. approval dan due schedule;
5. payment proposal;
6. `ProsesTransfer`/`DaftarPengajuanTransfer` mengeksekusi pembayaran;
7. allocation mengurangi open amount;
8. event memicu posting idempoten;
9. reversal tidak menghapus jurnal lama.

### UAT

- invoice duplicate vendor-number ditolak sesuai scope;
- invoice tanpa PO exception;
- partial invoice/payment;
- down payment dan termin;
- credit note;
- AP subledger sama dengan GL;
- posting source tidak dapat dibuat dua kali;
- period lock menolak backdate tanpa otorisasi.

### Gerbang lulus

PO, receipt, invoice, payment, dan journal dapat direkonsiliasi end-to-end.

### Rollback

AP baru berjalan shadow/read-only sebelum cutover. `SaldoAwalMasterAsset` baru
ditandai `RETIRE-WRITE` setelah satu periode rekonsiliasi disetujui.

## 16. Fase 11 — Laporan, read model, dan Control Tower

### Perubahan data

1. buat read model/materialized view per domain;
2. simpan watermark dan status refresh;
3. jangan membaca tabel transaksi besar tanpa filter/index;
4. semua angka drill-down ke source document;
5. export memakai snapshot/filter yang sama dengan layar.

### Laporan minimum

- demand, allocation, backorder, dan service level;
- PR/PO/receipt/invoice/payment aging;
- inventory balance, movement, expiry, slow/dead stock;
- warehouse productivity dan exception;
- transfer, shipment, OTIF, claim, dan POD;
- production plan/actual, yield, waste, dan variance;
- AP, cash requirement, GL reconciliation;
- sales, gross margin, dan replenishment feedback;
- audit trail serta health monitoring.

### UAT

- angka card = grid = export = drill-down;
- timezone dan tanggal bisnis konsisten;
- report besar memiliki pagination/server-side filter;
- refresh tidak mengunci transaksi;
- read model dapat dibangun ulang.

### Gerbang lulus

Seluruh KPI mempunyai definisi, owner, source, filter, dan query rekonsiliasi.

### Rollback

Read model dapat dinonaktifkan dan laporan kembali ke query existing tanpa mengubah
data transaksi.

## 17. Fase 12 — Paritas Desktop, Android, JSP, dan ZKoss

### Prinsip

Paritas berarti kesamaan capability dan aturan, bukan memaksakan layout identik.

### Pekerjaan

1. contract test semua endpoint;
2. matriks menu/action/platform;
3. responsive navigation dan work queue;
4. scan barcode/QR dan offline queue pada perangkat yang mendukung;
5. konflik versi dan optimistic locking;
6. error contract yang sama;
7. export/print mengikuti kemampuan platform;
8. dokumentasi bantuan kontekstual.

### UAT

- golden flow yang sama pada seluruh platform;
- hasil transaksi dan status sama;
- izin admin/non-admin sama;
- retry offline tidak membuat duplikasi;
- UI tidak menampilkan aksi yang akan selalu ditolak server.

### Gerbang lulus

Matriks parity ditandatangani product owner dan QA; tidak ada endpoint khusus platform
yang menulis domain dengan aturan berbeda.

### Rollback

Feature flag per platform dan per modul.

## 18. Fase 13 — Migrasi, pilot, cutover, dan rollout

### Urutan pilot

1. tenant/toko demo;
2. satu gudang dan satu outlet nonkritis;
3. satu rute distribusi;
4. satu jenis produksi;
5. satu vendor dan payment flow;
6. perluasan bertahap per tenant/lokasi.

### Tahapan setiap cutover writer

1. backfill;
2. checksum dan rekonsiliasi;
3. shadow read/write;
4. canary writer;
5. observasi;
6. writer target menjadi utama;
7. writer legacy read-only;
8. sign-off;
9. perluasan scope.

### UAT end-to-end wajib

1. outlet request, gudang cukup, distribusi, receipt outlet, produksi, POS;
2. outlet request, gudang kurang, PR, PO, receipt, distribusi, produksi, POS;
3. pembelian lokal outlet dengan approval;
4. partial, reject, return, cancel, reverse;
5. invoice, match, payment, posting, reversal;
6. offline/retry/duplicate/concurrency;
7. batch, expiry, quarantine, FEFO;
8. laporan dan audit trail.

### Gerbang lulus

- tidak ada duplicate movement, invoice, payment, atau posting;
- seluruh checksum sesuai;
- tidak ada transaksi hilang;
- performa memenuhi SLO;
- rollback rehearsal berhasil;
- business owner, Finance, Warehouse, dan IT menandatangani hasil.

### Rollback

Rollback dilakukan per writer/event type dan per lokasi, bukan rollback schema secara
destruktif. Writer target dihentikan, event canary direverse bila perlu, lalu adapter
legacy diaktifkan kembali.

## 19. Fase 14 — Stabilisasi dan dekomisioning legacy

### Pekerjaan

1. observasi minimal satu periode operasi yang disepakati;
2. tutup seluruh reconciliation exception;
3. tandai route/action/tabel legacy deprecated;
4. hentikan writer legacy;
5. archive mapping dan audit migration;
6. penghapusan fisik hanya pada release terpisah setelah backup, restore test, dan
   sign-off;
7. perbarui SOP, pelatihan, runbook, serta disaster recovery.

### Gerbang lulus

- tidak ada pembacaan/writer aktif yang bergantung pada artefak yang akan dihapus;
- monitoring stabil;
- restore dan replay event diuji;
- dokumentasi dan ownership operasional lengkap.

## 20. Paket implementasi per fase

Setiap fase coding wajib mempunyai struktur paket berikut:

1. **ADR** — keputusan dan trade-off;
2. **DDL additive** — up migration, constraint bertahap, index concurrent bila
   didukung;
3. **mapping** — existing-to-target per kolom;
4. **backfill** — resumable, idempotent, mempunyai checkpoint;
5. **domain service** — satu owner mutation;
6. **adapter legacy** — tanpa double-write independen;
7. **API contract** — request, response, error, idempotency;
8. **UI** — menu/action/responsive state;
9. **audit query** — before/after dan exception report;
10. **automated tests** — unit, integration, contract, concurrency;
11. **UAT script** — happy path dan exception;
12. **observability** — metric, structured log, trace/correlation;
13. **runbook** — deployment, verification, rollback;
14. **handover** — catatan di `/docs/pos/` termasuk revisi SVN dan commit Git.

## 21. Strategi branch, commit, dan deployment

1. satu fase tidak dibuat sebagai satu commit raksasa;
2. pisahkan commit registry/schema additive, backend, UI, migration, dan test;
3. jangan mencampur perubahan format massal yang tidak terkait;
4. server/API lebih dahulu backward-compatible;
5. client lama dan client baru harus dapat berjalan pada masa transisi;
6. baru setelah adopsi client cukup, kontrak legacy ditandai deprecated;
7. setiap deployment mencatat SVN revision, Git commit, migration batch, feature
   flag, dan hasil smoke test.

## 22. Definition of Done global

Implementasi keseluruhan belum selesai sampai:

- [ ] menu tidak redundan dan seluruh alias legacy terpetakan;
- [ ] `TbmroleAction` tetap menjadi sumber izin yang konsisten;
- [ ] admin melihat semua menu dan mutasinya diaudit;
- [ ] semua item, UOM, gudang, bin, lot, serta lokasi tidak ambigu;
- [ ] semua perubahan stok berasal dari ledger event kanonik;
- [ ] stock request, PR, PO, BAST, receipt, DO, shipment, POD, dan outlet receipt
      mempunyai fungsi terpisah;
- [ ] direct purchase tidak menggandakan receipt;
- [ ] produksi mempunyai material issue, output, waste, yield, dan cost trace;
- [ ] invoice AP, pembayaran, serta jurnal dapat direkonsiliasi;
- [ ] retry, concurrency, offline sync, dan reversal idempoten;
- [ ] laporan dapat drill-down ke source dan sama dengan export;
- [ ] Desktop, Android, JSP, dan ZKoss lulus parity matrix;
- [ ] seluruh migration checksum dan exception disetujui;
- [ ] rollback rehearsal berhasil;
- [ ] dokumentasi, SOP, monitoring, serta ownership operasional tersedia.

## 23. Urutan pekerjaan yang boleh langsung dimulai

Urutan sprint pertama yang aman:

1. selesaikan Fase 0 dan ADR keputusan schema;
2. implementasikan registry/action/alias Fase 1;
3. buat data dictionary fisik dan ERD dari Fase 2–3;
4. siapkan DDL additive fondasi master dan inventory ledger;
5. buat audit/backfill ledger dalam shadow mode;
6. baru mulai UI permintaan stok dan WMS setelah ledger shadow tervalidasi.

Fitur bisnis Fase 4 ke atas tidak boleh menjadi writer produksi sebelum ledger,
idempotency, registry action, dan reconciliation query lulus. Ini adalah batas teknis
utama agar modul baru tidak memperbanyak inkonsistensi existing.

