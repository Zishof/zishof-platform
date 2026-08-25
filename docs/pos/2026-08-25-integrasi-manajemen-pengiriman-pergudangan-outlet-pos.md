# Integrasi Manajemen Pengiriman, Pergudangan, Pengadaan, dan POS Outlet

Tanggal: 25 Agustus 2026  
Status: **analisis desain; belum ada perubahan kode atau schema database**  
Sumber rujukan: dokumen *Managemen Pengiriman Barang.pdf* (11 halaman) yang
disediakan pengguna. Isi dokumen diperlakukan sebagai referensi fungsi dan UI,
bukan instruksi eksekusi.

Dokumen terkait:

- [Analisis implementasi modul Pergudangan](2026-08-25-analisis-modul-pergudangan.md)
- [Fase implementasi modul Pergudangan](2026-08-25-fase-implementasi-modul-pergudangan.md)
- [Gap struktur tabel existing dan Pergudangan](2026-08-25-gap-struktur-tabel-pergudangan.md)
- [Integrasi Pergudangan dengan PR, PO, BAST, Tagihan, dan Pembayaran](2026-08-25-integrasi-pergudangan-pr-po-bast-tagihan.md)

## 1. Kesimpulan utama

Modul Manajemen Pengiriman harus menjadi jembatan operasional antara Pengadaan,
Pergudangan, outlet, dan POS. Modul ini tidak menggantikan PR, PO, Goods Receipt,
BAST, invoice pemasok, maupun pembayaran. Tugas utamanya adalah merencanakan dan
membuktikan perpindahan barang: kapasitas angkut, rute, layanan tambahan,
kepabeanan, biaya freight, tracking, serah terima, dan status barang dalam
perjalanan.

Rangkaian bisnis lengkap yang direkomendasikan:

```text
Kebutuhan/forecast/reorder
        -> PR -> persetujuan -> PO/kontrak
        -> pengiriman pemasok / Freight Order
        -> penerimaan gudang + QC + putaway
        -> BAST pengadaan
        -> terima invoice + matching
        -> persetujuan dan pembayaran pemasok
        -> permintaan replenishment outlet
        -> alokasi + picking + packing
        -> Delivery Order + shipment + tracking
        -> barang dalam perjalanan
        -> penerimaan outlet + selisih/QC + BAST distribusi
        -> stok outlet tersedia
        -> penjualan POS + pengurangan stok + HPP
        -> retur pelanggan/outlet/supplier bila diperlukan
```

Satu prinsip wajib berlaku di semua tahap: **hanya posting pergerakan stok yang
mengubah ledger persediaan**. PO, Freight Order, Delivery Order, BAST, invoice,
dan pembayaran tidak boleh membuat mutasi stok kedua.

## 2. Ruang lingkup fungsi dari dokumen rujukan

Fungsi yang terlihat pada dokumen Manajemen Pengiriman dan perlu diadaptasi:

1. otorisasi berbasis grup/peran `Freight Manager`;
2. pembuatan Freight Order berikut shipper, consignee, arah import/export,
   pelabuhan/lokasi asal-tujuan, moda, dan tanggal harapan;
3. rincian barang, kontainer, berat, volume, dasar penagihan, skema harga, harga
   satuan, serta total;
4. validasi kapasitas kontainer dan peringatan bila muatan berlebih;
5. rute operasional dan beberapa leg perjalanan;
6. layanan angkut dan layanan tambahan per vendor;
7. Customs Clearance dan revisi dokumen kepabeanan;
8. invoice biaya freight dari Freight Order;
9. tracking dengan nomor referensi, carrier, sumber, tujuan, tanggal, dan status;
10. laporan Freight Order dan riwayat tracking;
11. transfer stok antarperusahaan/antargudang, termasuk pembentukan dokumen
    receipt/delivery pada perusahaan tujuan;
12. status akhir barang telah dikirim dan diterima.

Untuk eBisnis/ECAMPUS, istilah perusahaan pada rujukan perlu dipetakan menjadi
tenant, satuan kerja, toko/outlet, atau legal entity sesuai konfigurasi. Perpindahan
antar-tenant tidak boleh otomatis dilakukan tanpa aturan kepemilikan, harga transfer,
dan otorisasi lintas entitas.

## 3. Pemisahan dokumen yang wajib dijaga

| Dokumen | Tujuan | Pemilik domain | Mengubah stok? |
|---|---|---|---:|
| PR | Permintaan kebutuhan | Pengadaan/pemohon | Tidak |
| PO | Komitmen beli, harga, jumlah, termin | Pengadaan | Tidak |
| Freight Order | Kontrak/rencana jasa angkut | Logistik | Tidak |
| Delivery Order | Instruksi dan manifest pengeluaran barang | Gudang/logistik | Tidak langsung |
| Shipment | Eksekusi perjalanan dan tracking | Logistik/carrier | Tidak langsung |
| Goods Issue | Posting barang keluar | Pergudangan | Ya |
| Goods Receipt | Posting jumlah fisik diterima | Pergudangan/outlet | Ya |
| BAST pengadaan | Pengakuan formal penerimaan dari pemasok | Pengadaan/penerima | Tidak; referensi receipt |
| BAST distribusi | Serah terima gudang-carrier-outlet | Logistik/outlet | Tidak; referensi issue/receipt |
| Invoice pemasok | Tagihan barang/jasa | Account Payable | Tidak |
| Invoice freight | Tagihan jasa pengiriman | Account Payable/logistik | Tidak |
| Pembayaran | Pelunasan utang | Kas/Bank | Tidak |
| Transaksi POS | Penjualan outlet | POS | Ya, melalui mutasi keluar idempoten |

Freight Order dan Delivery Order bukan sinonim. Freight Order mencakup kontrak
jasa angkut, kapasitas, rute, layanan, customs, dan biaya. Delivery Order adalah
instruksi operasional pelepasan barang tertentu dari sumber menuju tujuan.

## 4. Tiga skenario pengiriman

### 4.1 Pemasok ke gudang pusat

```text
PO -> ASN/pemberitahuan kirim -> Freight Order -> Shipment
   -> gate-in gudang -> bongkar -> Goods Receipt -> QC
   -> karantina/ditolak/lolos -> putaway -> BAST pengadaan
   -> invoice barang/freight -> matching -> pembayaran
```

Jumlah yang ditagih harus dibandingkan dengan PO dan receipt. Biaya freight dapat
menjadi beban langsung atau dialokasikan sebagai *landed cost* produk.

### 4.2 Gudang pusat ke outlet atau antargudang

```text
Replenishment/transfer request -> approval -> alokasi stok
 -> wave/picking -> packing -> Goods Issue
 -> Delivery Order -> Shipment/tracking -> in transit
 -> Goods Receipt outlet -> pemeriksaan selisih
 -> BAST distribusi -> putaway outlet -> available stock
```

Goods Issue sumber dan Goods Receipt tujuan adalah dua posting berbeda yang
diikat oleh satu `transfer_id` dan `shipment_id`. Selama perjalanan, nilai berada
pada akun/lokasi `inventory_in_transit`, bukan hilang dari sistem.

### 4.3 Pemasok langsung ke outlet (*drop shipment*)

PO tetap dimiliki Pengadaan, tetapi tujuan receipt adalah outlet. Outlet melakukan
penerimaan dan BAST. Gudang pusat tidak membuat stok masuk/keluar fiktif. Freight
Order mereferensikan PO serta outlet tujuan, dan invoice tetap menjalani matching.

## 5. Hubungan PR dan PO

PR dapat menghasilkan satu atau beberapa PO; satu PO dapat menghasilkan beberapa
jadwal pengiriman, Freight Order, Delivery Order, shipment, dan receipt parsial.

Relasi minimum:

```text
purchase_request
  1 -> n purchase_request_item
  n -> n purchase_order_item (melalui sumber kebutuhan)

purchase_order
  1 -> n purchase_order_item
  1 -> n purchase_order_term
  1 -> n inbound_shipment / freight_order
  1 -> n goods_receipt
```

### 5.1 PO bukan termin

Pembayaran biasanya dilakukan setelah barang diterima dan dokumen lolos matching.
Pengiriman dan penerimaan parsial tetap harus didukung; status PO menjadi selesai
hanya setelah toleransi kuantitas, retur, dan sisa pesanan diselesaikan.

### 5.2 PO termin

Termin dan pengiriman adalah dimensi berbeda. Contohnya uang muka, pembayaran saat
barang dikirim, pembayaran setelah receipt minimum, serta pelunasan setelah BAST.
Pemenuhan milestone termin dapat membaca status shipment/receipt/BAST, tetapi tidak
boleh membuat mutasi persediaan.

## 6. Hubungan BAST, terima tagihan, dan pembayaran

BAST perlu memiliki jenis agar maknanya tidak tercampur:

- `PENGADAAN_BARANG`: pemasok menyerahkan ke gudang/outlet;
- `JASA_FREIGHT`: carrier menyelesaikan jasa/leg;
- `DISTRIBUSI_OUTLET`: gudang/carrier menyerahkan ke outlet;
- `RETUR`: penyerahan barang retur ke gudang/pemasok/carrier;
- `JASA_LAIN`: penyelesaian pekerjaan nonbarang.

Invoice barang memakai 3-way atau 4-way matching:

```text
PO <-> Goods Receipt <-> Invoice [<-> BAST]
```

Invoice freight memakai:

```text
Freight Order/kontrak tarif <-> shipment/leg selesai
<-> BAST jasa freight <-> invoice freight
```

Pembayaran hanya boleh diproses setelah hasil matching dan approval memenuhi
kebijakan. Untuk PO termin, tagihan harus menyimpan `purchase_order_term_id` dan
bukti milestone yang dipakai.

## 7. Proses distribusi sampai outlet

### 7.1 Permintaan dan alokasi

Permintaan dapat berasal dari outlet, min-max stock, forecast, reorder point, atau
alokasi pusat. Sistem memeriksa saldo tersedia, reservasi, batch, FEFO, dan batas
kapasitas outlet sebelum membuat transfer.

### 7.2 Picking dan packing

- reservasi stok dilakukan per gudang dan lokasi/bin;
- batch/serial/expired dipilih dengan FEFO bila relevan;
- hasil picking harus dapat berbeda dari rencana dengan reason code;
- packing menghasilkan package/pallet/container dan barcode/QR;
- manifest Delivery Order mengambil data hasil packing, bukan hanya permintaan.

### 7.3 Dispatch dan tracking

Ketika kendaraan/carrier berangkat, gudang mem-posting Goods Issue. Shipment
menyimpan leg, ETA, carrier, kendaraan, pengemudi, tracking reference, bukti foto,
GPS bila tersedia, dan event status. Event harus append-only untuk audit.

### 7.4 Penerimaan outlet

Outlet memindai Delivery Order/package, lalu mencatat jumlah diterima, rusak,
kurang, lebih, dan ditolak per item/batch. Receipt tidak boleh sekadar menyalin
jumlah kirim. Selisih membuat exception yang harus diselesaikan gudang/logistik.

Setelah receipt diposting:

- stok in-transit berkurang;
- stok outlet bertambah pada lokasi penerimaan/karantina;
- barang QC lulus dipindahkan ke rak jual;
- BAST distribusi ditandatangani;
- status shipment menjadi `DELIVERED`, `PARTIALLY_RECEIVED`, atau `DISPUTED`.

## 8. Retur di outlet

Retur harus dibedakan berdasarkan sumber dan tujuan:

| Jenis retur | Sumber -> tujuan | Dampak utama |
|---|---|---|
| Retur pelanggan POS | Pelanggan -> outlet | Refund/credit dan stok retur/karantina |
| Retur outlet ke gudang | Outlet -> gudang pusat | Transfer balik dengan issue/receipt |
| Retur pembelian | Gudang/outlet -> pemasok | Mutasi keluar dan debit note/koreksi AP |
| Gagal kirim/RTS | Carrier -> gudang/outlet asal | Pembalikan shipment, bukan penjualan baru |
| Retur rusak/kedaluwarsa | Outlet -> karantina/pemusnahan/pemasok | Disposition dan approval khusus |

Setiap retur memerlukan referensi transaksi asal bila tersedia, reason code,
disposition, quantity, batch/serial, nilai, pihak penanggung biaya, dan bukti.
Re-delivery menggunakan shipment baru tetapi tetap di bawah kasus retur yang sama.

## 9. Hubungan dengan penjualan POS outlet

POS hanya dapat menjual stok outlet yang `AVAILABLE`, bukan `IN_TRANSIT`,
`QUARANTINE`, `DAMAGED`, atau `RESERVED` untuk proses lain. Ketika pembayaran POS
berhasil:

1. transaksi disimpan idempoten dengan kode unik;
2. mutasi stok keluar dibuat satu kali;
3. batch dipilih mengikuti FEFO/kebijakan;
4. HPP dicatat dari valuasi yang berlaku;
5. backup lokal dan sinkronisasi tidak boleh membuat mutasi kedua;
6. retur POS mereferensikan transaksi dan item asal.

Riwayat asal stok perlu dapat ditelusuri:

```text
Penjualan POS -> batch outlet -> receipt outlet -> shipment/DO
 -> issue gudang -> batch gudang -> receipt pemasok -> PO/supplier
```

Traceability ini penting untuk recall produk, kedaluwarsa, audit selisih, dan
penentuan tanggung jawab retur.

## 10. Status yang disarankan

### 10.1 Freight Order

`DRAFT -> QUOTED -> CONFIRMED -> IN_PROGRESS -> COMPLETED -> INVOICED -> CLOSED`

Cabang: `CANCELLED`, `ON_HOLD`, `CUSTOMS_HOLD`.

### 10.2 Delivery Order

`DRAFT -> ALLOCATED -> PICKING -> PICKED -> PACKED -> READY_TO_DISPATCH -> DISPATCHED -> DELIVERED -> CLOSED`

Cabang: `PARTIALLY_DELIVERED`, `FAILED_DELIVERY`, `RETURN_TO_SENDER`, `CANCELLED`.

### 10.3 Shipment

`PLANNED -> BOOKED -> PICKED_UP -> IN_TRANSIT -> ARRIVED -> UNLOADING -> DELIVERED`

Event antara dapat berupa `CUSTOMS_SUBMITTED`, `CUSTOMS_CLEARED`, `DELAYED`,
`DAMAGED`, atau `LOST`.

### 10.4 Penerimaan outlet

`DRAFT -> COUNTING -> QC_PENDING -> POSTED -> BAST_SIGNED -> CLOSED`

Cabang: `PARTIAL`, `DISPUTED`, `QUARANTINED`, `REJECTED`.

Status tidak boleh dilompati hanya karena UI menekan tombol selesai. Perubahan
status harus tervalidasi, berotorisasi, dan tercatat pada audit trail.

## 11. Rancangan relasi data konseptual

Nama berikut adalah rancangan logis, bukan keputusan nama tabel final:

```text
purchase_request -> purchase_order -> purchase_order_term
purchase_order -> freight_order -> freight_order_item
freight_order -> freight_container
freight_order -> freight_route -> freight_route_operation
freight_order -> freight_service
freight_order -> customs_clearance -> customs_revision
freight_order -> freight_invoice

transfer_request -> transfer_order -> delivery_order -> shipment
delivery_order -> delivery_order_item -> shipment_package
shipment -> shipment_leg -> shipment_tracking_event
shipment -> goods_issue (source warehouse)
shipment -> outlet_receipt -> outlet_receipt_item
outlet_receipt -> bast (distribution)

goods_receipt -> bast (procurement)
purchase_order + goods_receipt + bast -> vendor_invoice
vendor_invoice -> invoice_match_result -> payment_request -> payment

outlet_receipt -> outlet stock -> POS sale -> POS return
return_order -> return_item -> return shipment -> return receipt
```

Kolom referensi lintas proses minimal:

- `tenant_id`, `legal_entity_id`, `source_warehouse_id`, `destination_outlet_id`;
- `document_no`, `external_reference`, `idempotency_key`;
- `pr_id`, `po_id`, `po_item_id`, `term_id`;
- `freight_order_id`, `delivery_order_id`, `shipment_id`, `shipment_leg_id`;
- `goods_issue_id`, `goods_receipt_id`, `bast_id`;
- `vendor_invoice_id`, `payment_id`, `pos_transaction_id`, `return_order_id`;
- `product_id`, `batch_id`, `serial_no`, `quantity`, `uom_id`;
- `created_by`, `approved_by`, `posted_by`, waktu, versi, dan reason code.

## 12. Pemanfaatan tabel existing dan gap

Implementasi tidak boleh membuat ledger stok ketiga. Kandidat sumber kebenaran
tetap ledger tenant `{S}.mutasi_stok`, dengan saldo/materialized balance yang
diturunkan secara aman. Tabel legacy berikut perlu diperlakukan sebagai sumber
migrasi atau adapter, bukan langsung diduplikasi:

- `asset.pengiriman_gudang` dan `asset.pengiriman_gudang_detail`;
- `koperasi.mutasi_stok_toko`;
- `koperasi.produk_batch`;
- `koperasi.pengadaan_faktur` dan `koperasi.pengadaan_produk`;
- `koperasi.retur_pembelian` dan `koperasi.retur_penjualan`.

Gap utama terhadap kebutuhan pengiriman:

- belum ada model Freight Order lengkap untuk kontainer, rute, layanan, dan customs;
- status transfer/pengiriman belum cukup rinci;
- belum ada package/manifest serta tracking event append-only;
- belum ada stok in-transit yang konsisten antar source dan destination;
- receipt outlet, selisih, BAST distribusi, dan retur belum terikat end-to-end;
- biaya freight dan landed cost belum dialokasikan secara eksplisit;
- idempotensi integrasi carrier/offline POS perlu kontrak formal.

## 13. Biaya freight dan akuntansi

Komponen biaya dapat meliputi transport utama, first/last mile, handling,
container, customs, asuransi, storage, demurrage, dan layanan tambahan. Alokasi
landed cost dapat berdasarkan berat, volume, kuantitas, nilai barang, atau formula
manual yang diaudit.

Jurnal konseptual:

- Goods Issue transfer: `Dr Persediaan Dalam Perjalanan / Cr Persediaan Gudang`;
- Receipt outlet: `Dr Persediaan Outlet / Cr Persediaan Dalam Perjalanan`;
- Freight-in kapitalisasi: `Dr Persediaan / Cr Utang Freight`;
- Freight sebagai beban: `Dr Beban Pengiriman / Cr Utang Freight`;
- penjualan POS: `Dr Kas/Piutang / Cr Penjualan` dan `Dr HPP / Cr Persediaan`;
- retur pelanggan: pembalikan penjualan/HPP sesuai kondisi barang;
- retur pemasok: koreksi persediaan, utang, pajak, dan debit note.

Nilai finansial tidak boleh dibentuk dari tracking saja. Tracking membuktikan
eksekusi, sedangkan posting akuntansi memakai dokumen dan approval yang sah.

## 14. Pencegahan duplikasi dan konsistensi

Setiap operasi posting harus memiliki `idempotency_key` stabil, unique constraint,
dan hasil yang dapat dipanggil ulang tanpa efek ganda. Kunci disarankan mencakup
tenant, jenis dokumen, nomor dokumen sumber, versi/revisi, dan tipe posting.

Aturan wajib:

- satu Delivery Order tidak boleh membentuk Goods Issue dua kali;
- satu receipt tidak boleh menambah stok dua kali saat retry;
- event tracking dari carrier dideduplikasi dengan `carrier_event_id`;
- sinkronisasi offline outlet/POS memakai kode transaksi global dan versioning;
- perubahan jumlah setelah posting memakai reversal/correction, bukan overwrite;
- transaksi lintas gudang memakai locking/reservation untuk mencegah oversell;
- pembuatan otomatis receipt/delivery antarentitas harus transactional dan dapat
  dilanjutkan bila sebagian proses gagal.

## 15. Peran dan otorisasi

Peran minimum:

- pemohon PR dan approver;
- buyer/purchasing manager;
- freight/logistics planner dan Freight Manager;
- petugas customs;
- picker, packer, dispatcher, dan checker gudang;
- driver/carrier integration;
- penerima dan supervisor outlet;
- QC dan petugas retur;
- AP verifier, payment approver, kas/bank;
- kasir POS dan supervisor POS;
- auditor/read-only.

Pemisahan tugas harus mencegah orang yang sama membuat, menyetujui, menerima,
menagihkan, dan membayar dokumen bernilai material tanpa kontrol tambahan.

## 16. Rancangan menu

```text
Pergudangan
  - Permintaan Transfer/Replenishment
  - Alokasi & Reservasi
  - Picking
  - Packing & Manifest
  - Delivery Order
  - Penerimaan Gudang/Outlet
  - Putaway
  - QC & Karantina
  - Retur

Manajemen Pengiriman
  - Freight Order
  - Kontainer & Kapasitas
  - Rute & Leg
  - Layanan & Tarif
  - Customs Clearance
  - Dispatch
  - Tracking
  - Exception/Claim
  - Invoice Freight

Outlet
  - Barang Dalam Perjalanan
  - Terima Barang
  - Selisih & BAST
  - Retur ke Gudang/Pemasok
  - Stok Siap Jual
  - POS/Kasir
```

Dashboard harus menunjukkan jumlah shipment terlambat, in-transit, customs hold,
receipt belum diposting, selisih penerimaan, retur terbuka, serta stok outlet yang
terancam habis.

## 17. API dan integrasi

Kontrak API perlu mendukung pagination, filter tanggal/status, delta sync, ETag
atau versi, dan idempotency. Endpoint konseptual:

- `freight_order_create/update/confirm/list/detail`;
- `freight_capacity_check`;
- `delivery_order_allocate/pick/pack/dispatch`;
- `shipment_tracking_event_push/list`;
- `outlet_receipt_create/count/post`;
- `bast_create/sign`;
- `return_create/dispatch/receive/dispose`;
- `invoice_match_run/approve`;
- `stock_trace_by_batch/transaction`.

Mobile outlet perlu dapat menerima barang saat koneksi tidak stabil. Receipt lokal
harus tersimpan lebih dahulu, lalu dikirim ulang dengan idempotency key yang sama.
Konflik jumlah harus masuk antrean resolusi, bukan ditimpa otomatis.

## 18. Laporan dan KPI

- PO outstanding dan inbound ETA;
- ketepatan pengiriman pemasok/carrier (OTIF);
- utilisasi berat/volume kontainer;
- biaya freight per kg, volume, item, rute, outlet, dan vendor;
- lead time PR-to-PO, PO-to-receipt, gudang-to-outlet;
- dwell time customs, gudang, dan unloading outlet;
- shipment terlambat, gagal kirim, rusak, hilang, dan klaim;
- selisih shipped-vs-received per outlet/carrier;
- stok in-transit dan aging;
- fill rate permintaan outlet;
- retur pelanggan, outlet, gudang, dan pemasok;
- traceability batch dari pemasok hingga transaksi POS;
- invoice freight belum matching dan pembayaran jatuh tempo.

## 19. Fase implementasi

### Fase 0 — keputusan desain dan data cleansing

- tetapkan tenant/legal entity/gudang/outlet dan ledger canonical;
- audit tabel pengiriman/transfer legacy;
- tetapkan nomor dokumen, status, tolerance, dan idempotency;
- tetapkan pemisahan BAST pengadaan, freight, dan distribusi.

### Fase 1 — distribusi internal minimum

- transfer request, allocation, picking, packing, Delivery Order;
- Goods Issue, in-transit, receipt outlet, selisih, dan putaway;
- audit trail dan laporan dasar.

### Fase 2 — Freight Order dan tracking

- kontainer/kapasitas, rute/leg, layanan, tarif, carrier;
- tracking event, ETA, exception, proof of delivery;
- integrasi BAST distribusi.

### Fase 3 — procurement dan AP end-to-end

- inbound shipment dari PO;
- BAST pengadaan dan jasa freight;
- invoice matching, landed cost, termin, dan pembayaran.

### Fase 4 — retur dan traceability

- retur pelanggan, outlet, gudang, pemasok, RTS;
- quarantine/disposition/credit note;
- penelusuran batch hingga POS.

### Fase 5 — optimasi

- wave picking, route optimization, carrier SLA;
- forecast replenishment;
- integrasi GPS/carrier/customs;
- analitik biaya dan performa.

## 20. UAT minimum

1. satu PO dikirim dalam tiga shipment dan diterima parsial;
2. PO termin dengan uang muka, milestone receipt, dan BAST final;
3. kapasitas kontainer terlampaui dan sistem menolak/menawarkan split;
4. shipment multi-leg dengan customs hold dan revisi dokumen;
5. transfer gudang ke outlet, issue sumber dan receipt tujuan seimbang;
6. outlet menerima kurang/rusak dan membuat dispute tanpa menambah stok salah;
7. retry posting issue/receipt tidak menciptakan mutasi ganda;
8. tracking event duplikat tidak menggandakan status;
9. retur outlet ke gudang lalu retur pemasok;
10. produk hasil receipt outlet dapat dijual di POS dan HPP benar;
11. retur POS mengembalikan stok ke lokasi sesuai disposition;
12. traceability batch dari struk POS sampai PO/supplier berhasil;
13. invoice barang dan freight yang tidak match ditahan;
14. pembayaran termin tidak mengubah stok;
15. transaksi antar-tenant ditolak bila konfigurasi dan otorisasi tidak sah.

## 21. Keputusan yang masih diperlukan

- apakah transfer antar-outlet berada dalam satu legal entity atau dapat lintas
  entitas;
- kapan Goods Issue diposting: saat loading, gate-out, atau carrier pickup;
- kapan stok outlet menjadi available: saat receipt atau setelah QC/putaway;
- apakah freight dikapitalisasi penuh, sebagian, atau menjadi beban;
- jenis BAST dan tanda tangan elektronik yang diwajibkan;
- kebijakan toleransi kurang/lebih/rusak dan siapa approver-nya;
- mode integrasi carrier/customs serta sumber status final;
- retensi data tracking/GPS dan bukti foto;
- aturan retur pelanggan tanpa struk dan retur antar-outlet;
- strategi migrasi dari tabel pengiriman/transfer legacy.

Keputusan tersebut harus diselesaikan sebelum fase schema fisik agar modul tidak
membentuk ledger, status, atau dokumen ganda yang sulit direkonsiliasi.
