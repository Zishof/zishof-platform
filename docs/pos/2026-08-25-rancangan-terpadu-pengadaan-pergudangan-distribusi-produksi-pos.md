# Rancangan terpadu Pengadaan, Pergudangan, Distribusi, Produksi, dan POS

Tanggal: 25 Agustus 2026  
Status: **analisis desain dan rencana implementasi; belum mengubah schema atau kode bisnis**  
Repository yang diperiksa:

- server ECAMPUS/eBisnis: `C:\opt\AIS\ais`;
- Desktop/Mobile dan dokumen handover: `C:\opt\CodeBaseDesktopDanMobile`.

## 1. Tujuan

Dokumen ini menjawab keputusan utama berikut:

1. apakah tabel Pengadaan existing perlu dipakai ulang atau diganti;
2. apakah PO termin dan nontermin perlu tabel terpisah;
3. apakah Freight Order, Delivery Order, Shipment, dan BAST outlet boleh digabung
   dengan PR/PO/BAST supplier;
4. bagaimana menghubungkan permintaan outlet, pengadaan vendor, pergudangan,
   pengiriman, penerimaan outlet, produksi, dan POS tanpa stok atau tagihan ganda;
5. gap struktur existing serta fase implementasi menjadi kode.

## 2. Kesimpulan eksekutif

Rekomendasi final adalah **arsitektur hibrida: reuse workflow Pengadaan/Keuangan,
tetapi pisahkan dokumen operasional Pergudangan dan Distribusi**.

Keputusannya:

| Area | Keputusan | Alasan utama |
|---|---|---|
| PR/PO/BAST external vendor existing | **Pertahankan untuk kompatibilitas, lalu perluas melalui adapter/facade** | Workflow persetujuan, vendor, SOP, nilai, pajak, termin, dan pembayaran sudah matang. |
| Detail PR/PO/BAST untuk barang dagang/bahan | **Jangan langsung memaksa `Produk` masuk ke kolom `MasterAsset`** | Detail existing terikat `MasterAsset`, sedangkan stok/POS memakai `Produk`; kedua domain tidak identik. |
| PO termin dan nontermin | **Satu aggregate PO, tidak perlu dua tabel header** | Existing sudah memiliki `byTermin`, `poInduk`, pembayaran DP, dan pembayaran termin. |
| Terima tagihan `SaldoAwalMasterAsset*` | **Reuse jangka pendek melalui nama bisnis “Tagihan Vendor”; migrasikan bertahap** | Secara implementasi memang berfungsi sebagai invoice/AP, tetapi nama tabelnya menyesatkan dan domainnya masih MasterAsset. |
| `DaftarPengajuanTransfer` dan `ProsesTransfer` | **Reuse** | Keduanya sudah menjadi workflow pengajuan dan realisasi pembayaran lintas sumber. |
| Permintaan stok outlet | **Tabel/dokumen baru** | Ini permintaan replenishment internal, bukan PR pembelian vendor. |
| Transfer Order/Delivery Order/Shipment | **Tabel/dokumen operasional terpisah namun saling terkait** | Masing-masing mewakili instruksi stok, surat jalan, dan eksekusi perjalanan yang berbeda. |
| Freight Order | **Terpisah dari PO barang dan DO** | FO adalah pemesanan jasa angkut; dapat ditautkan ke kontrak/PO jasa dan beberapa shipment. |
| BAST supplier dan BAST outlet | **Jangan menjadi satu dokumen tanpa tipe dan sumber yang eksplisit** | Supplier receipt mengakui barang dari vendor; outlet receipt mengakui transfer internal. Dampak kepemilikan, akuntansi, dan exception berbeda. |
| Ledger stok | **Satu ledger kanonis** | Gunakan kandidat tenant `{S}.mutasi_stok`; semua dokumen hanya mem-posting ke ledger secara idempoten. |
| Produksi outlet | **Dokumen produksi/BOM terpisah** | Pemakaian bahan dan penerimaan hasil jadi harus dapat diaudit, bukan hanya mengubah angka stok. |

Dengan desain ini, alur lama tetap berjalan dan tidak dibuat duplikat PR/PO/AP yang
bersaing. Tabel baru hanya dibuat untuk kapabilitas yang memang belum diwakili
secara benar oleh tabel existing.

## 3. Bukti dari kode existing

### 3.1 PR existing

| Tabel/entity | Bukti penting | Makna |
|---|---|---|
| `asset.permintaan_pengadaan_master_asset` / `PermintaanPengadaanMasterAsset` | kode, toko, workspace, satuan kerja, nilai, SOP, approval/rejection, link PO | Header PR dan workflow persetujuan sudah tersedia. |
| `asset.permintaan_pengadaan_master_asset_detail` / detail | `MasterAsset`, jumlah, harga beli, harga total, link PO detail | Detail khusus katalog aset, bukan katalog `Produk` POS. |

### 3.2 PO existing

| Tabel/entity | Bukti penting | Makna |
|---|---|---|
| `asset.pemesanan_pengadaan_master_asset` / `PemesananPengadaanMasterAsset` | penyedia, nilai, pajak, uang muka, lunas/dibayar, `byTermin`, `pembelianLangsung`, `poInduk`, tanggal batas pengiriman | Header PO cukup matang dan sudah mendukung pembelian langsung serta termin. |
| `asset.pemesanan_pengadaan_master_asset_detail` / detail | `MasterAsset`, qty, harga, diskon/pajak, link PR detail dan penerimaan detail | Traceability PR-PO-penerimaan ada, tetapi item masih domain aset. |

**Keputusan:** jangan membuat tabel `po_termin` dan `po_nontermin` sebagai dua
header terpisah. Variasi pembayaran adalah kebijakan/schedule pada satu PO.

### 3.3 Penerimaan/BAST supplier existing

| Tabel/entity | Bukti penting | Makna |
|---|---|---|
| `asset.penerimaan_pengadaan_master_asset` / `PenerimaanPengadaanMasterAsset` | link PO, penyedia, kode/tanggal tagihan, kurir, jenis penerimaan, termin, posting history | Mewakili penerimaan formal dari supplier dan sudah berkaitan dengan tagihan. |
| `asset.penerimaan_pengadaan_master_asset_detail` / detail | `MasterAsset`, qty diterima, kondisi, harga, garansi, link PO/PR/tagihan detail | Baik untuk BAST aset, tetapi belum cukup untuk WMS: batch, expiry, QC, bin, UOM, accepted/rejected, dan putaway. |

### 3.4 Terima tagihan existing

`asset.saldo_awal_master_asset` dan detailnya, walaupun bernama “saldo awal”,
secara nyata memuat vendor, nilai, dibayar/lunas, kode dan tanggal tagihan, termin,
link penerimaan, pajak, serta `DaftarPengajuanTransfer`. Jadi modul sekarang
memakainya sebagai invoice/utang vendor.

Masalahnya bukan fungsi yang tidak ada, melainkan:

- nama teknis tidak merepresentasikan fungsi bisnis;
- detail terikat `MasterAsset`;
- relasi satu-ke-satu dengan penerimaan dapat terlalu sempit untuk invoice yang
  menggabungkan beberapa receipt atau receipt yang ditagih bertahap;
- belum ada struktur matching item PO-receipt-invoice yang eksplisit.

**Keputusan transisi:** tetap gunakan tabel ini agar fungsi lama tidak rusak,
bungkus dengan service/facade bernama bisnis `TagihanVendor`, lalu siapkan migrasi
ke aggregate invoice generik apabila volume dan variasi proses sudah tervalidasi.

### 3.5 Pembayaran existing

| Tabel/entity | Bukti penting | Keputusan |
|---|---|---|
| `asset.pembayaran_dp_master_asset*` | pembayaran DP dan link PO/pengajuan transfer | Reuse. |
| `asset.pembayaran_termin_master_asset*` | pembayaran termin, penalti, total dibayar, tagihan, tanggal transaksi | Reuse. |
| `asset.pembayaran_pengadaan_master_asset*` | pembayaran penerimaan/tagihan | Reuse. |
| `akunting.daftar_pengajuan_transfer` | satu detail pengajuan dapat menunjuk DP, termin, tagihan, dan sumber lain | Reuse sebagai payment request. |
| `akunting.proses_transfer` | batch/realisasi transfer, metode, nilai, approval | Reuse sebagai payment execution. |

Pergudangan tidak perlu membuat tabel pembayaran sendiri. Ia hanya menyediakan
bukti penerimaan/QC/BAST sebagai prasyarat verifikasi tagihan.

### 3.6 Pengiriman dan stok existing

| Tabel/entity | Kondisi existing | Penilaian |
|---|---|---|
| `asset.pengiriman_gudang` | asal, tujuan, transit, kirim/terima, status, pengirim/penerima | Fondasi transfer/DO legacy, tetapi state bebas dan belum mempunyai allocation, package, tracking event, atau idempotent stock posting. |
| `asset.pengiriman_gudang_detail` | `Produk`, qty kirim/terima/rusak, harga | Sudah memakai domain produk, tetapi belum batch/expiry/UOM/bin. |
| `koperasi.mutasi_stok_toko` | produk dan toko asal/tujuan, qty/waktu | Transfer sederhana, bukan ledger WMS lengkap. |
| `{S}.mutasi_stok` | gudang, lokasi, batch, dokumen sumber, reversal, idempotency, correlation | Kandidat ledger stok kanonis. |
| `koperasi.produksi_kantin` | produk hasil, toko, rencana/dibuat/terjual/sisa/waste | Header produksi sederhana. |
| `koperasi.pemakaian_bahan_baku` | produk bahan, toko, qty, waktu, transaksi POS opsional | Pemakaian bahan ada, tetapi belum memiliki BOM/order produksi/lot genealogy. |

## 4. Pemisahan domain yang wajib dijaga

### 4.1 Permintaan stok outlet bukan PR pembelian

Permintaan outlet ke gudang utama adalah **internal stock request/replenishment**.
PR pembelian adalah permintaan organisasi kepada fungsi procurement untuk membeli
dari pihak eksternal.

Satu permintaan stok outlet dapat menghasilkan:

- pemenuhan penuh dari stok gudang;
- pemenuhan parsial dari stok dan sisanya PR vendor;
- backorder;
- pembelian lokal outlet dengan otorisasi;
- penolakan/substitusi.

Karena itu harus ada dokumen `permintaan_stok_outlet` sendiri. Bila stok kurang,
baris kekurangan dapat menghasilkan PR existing dan menyimpan relasi asalnya.

### 4.2 `MasterAsset` dan `Produk` tidak boleh dicampur diam-diam

`MasterAsset` cocok untuk aset/barang pengadaan umum. `Produk` adalah katalog
inventory dan POS. Bahan baku, setengah jadi, dan barang jadi harus mempunyai
identitas inventory yang dapat memiliki UOM, batch, expiry, stok, BOM, dan harga.

Pilihan implementasi yang direkomendasikan:

1. buat kontrak generik `item_ref_type` + `item_ref_id` pada detail procurement
   baru/bridge; atau
2. buat `katalog_item_pengadaan` yang memetakan `Produk` dan `MasterAsset` ke satu
   identitas procurement; atau
3. untuk fase transisi, buat tabel bridge `pengadaan_produk_link` yang
   menghubungkan detail PR/PO/receipt existing ke `Produk`.

Pilihan (2) paling sehat untuk jangka panjang. Pilihan (3) paling rendah risiko
untuk pilot karena tidak mengubah seluruh layar pengadaan sekaligus.

## 5. Model dokumen target dan keputusan reuse

| Dokumen target | Reuse existing? | Catatan |
|---|---:|---|
| Permintaan Stok Outlet | Tidak | Baru; kebutuhan internal outlet. |
| Alokasi/Reservasi Gudang | Tidak | Baru; mengikat stok tersedia tanpa mengurangi on-hand. |
| Transfer Order | Sebagian | Adapter/migrasi dari `pengiriman_gudang`; instruksi perpindahan internal. |
| Picking/Packing | Tidak | Baru; eksekusi operasional gudang. |
| Delivery Order/Surat Jalan | Sebagian | Dapat memakai identitas pengiriman legacy, tetapi lebih aman aggregate tenant yang eksplisit. |
| Shipment | Tidak | Baru; kendaraan/kurir, paket, tracking, leg, proof of delivery. |
| Freight Order | Tidak | Baru; order jasa angkut, tarif, carrier, SLA, biaya. |
| Penerimaan Outlet/BAST Internal | Tidak | Baru; mengakui qty diterima/rusak/selisih atas DO. |
| PR Vendor | Ya | Existing, melalui adapter item produk. |
| PO Vendor | Ya | Existing; satu header mendukung termin/nontermin. |
| Inbound Shipment Vendor | Tidak | Baru bila dibutuhkan ASN/tracking supplier. |
| Goods Receipt/QC/Putaway Gudang | Sebagian | BAST existing tetap formal; proses WMS fisik perlu tabel baru. |
| Tagihan Vendor | Ya, transisi | Facade atas `SaldoAwalMasterAsset`, lalu migrasi jika diperlukan. |
| Pembayaran | Ya | `DaftarPengajuanTransfer` dan `ProsesTransfer`. |
| Production Order/BOM | Sebagian | Perlu aggregate baru; data produksi/pemakaian lama menjadi adapter. |
| Penjualan POS | Ya | Tetap memakai transaksi POS dan mem-posting stock issue. |

## 6. Alur bisnis target

```text
MIN/MAX stok outlet atau permintaan manual
                 |
                 v
       Permintaan Stok Outlet
                 |
        +--------+---------+
        |                  |
  stok gudang cukup   stok gudang kurang
        |                  |
        |          PR -> PO -> Inbound Shipment
        |                  |
        |          Goods Receipt -> QC -> Putaway
        |                  |
        +--------<---------+
                 |
       Reservasi -> Picking -> Packing
                 |
       Transfer Order -> Delivery Order
                 |
        Freight Order (jika carrier eksternal)
                 |
              Shipment
                 |
      Penerimaan/BAST Outlet
                 |
        Stok bahan/setengah jadi
                 |
     Production Order -> Issue Bahan
                 |
     Finished Goods Receipt + Waste
                 |
              POS Sale
                 |
       saldo <= reorder point
                 |
          proses berulang
```

### 6.1 Skenario stok gudang tersedia

1. Outlet mengirim permintaan stok.
2. Gudang memeriksa `available = on_hand - reserved`.
3. Sistem membuat reservasi/alokasi.
4. Petugas picking dan packing.
5. Sistem membuat DO dan shipment.
6. Saat dispatch, ledger membuat movement OUT gudang dan IN_TRANSIT.
7. Outlet menerima dan mencatat selisih/rusak.
8. Saat BAST outlet diposting, IN_TRANSIT dikurangi dan stok outlet bertambah.
9. Selisih menghasilkan claim, return, atau adjustment dengan approval.

### 6.2 Skenario stok gudang kurang

1. Baris kekurangan menjadi backorder.
2. Procurement proposal menggabungkan kebutuhan beberapa outlet agar tidak
   membuat PR kecil berulang.
3. PR existing dibuat dengan referensi permintaan stok sumber.
4. PO dibuat kepada vendor; termin/nontermin tetap dalam satu aggregate.
5. Barang datang melalui inbound shipment, receiving, QC, dan putaway.
6. Baris backorder dialokasikan kembali otomatis berdasarkan prioritas.
7. Proses DO/shipment ke outlet berjalan seperti skenario stok tersedia.

### 6.3 Pembelian lokal outlet

Pembelian lokal hanya boleh jika:

- item diizinkan oleh kebijakan;
- gudang pusat menyatakan tidak tersedia atau lead time tidak memenuhi;
- vendor outlet disetujui;
- limit nilai dan approver terpenuhi;
- dokumen tetap masuk PR/PO/receipt/tagihan/payment yang sama atau jalur
  `pembelianLangsung` existing;
- penerimaan lokal tetap mem-posting ledger outlet, batch, dan expiry.

Pembelian lokal bukan alasan untuk memasukkan stok tanpa dokumen.

### 6.4 Produksi outlet dan POS

1. BOM menentukan bahan per satuan hasil.
2. Production Order mereservasi bahan.
3. Material Issue mem-posting movement OUT bahan per batch/FEFO.
4. Finished Goods Receipt mem-posting movement IN barang siap saji.
5. Waste/yield variance dicatat terpisah.
6. POS menjual barang jadi dan mem-posting movement OUT barang jadi.
7. Bila produk dibuat saat dipesan, POS dapat memicu backflush bahan dengan
   idempotency key transaksi + detail.

## 7. Relasi PR, PO, BAST, tagihan, pembayaran, FO, DO, dan shipment

```text
PermintaanStokOutletDetail
  |-- AlokasiStokDetail -> TransferOrderDetail
  |                         `-> DeliveryOrderDetail -> ShipmentPackageDetail
  |                                                   `-> PenerimaanOutletDetail
  `-- KekuranganPengadaan -> PermintaanPengadaanMasterAssetDetail (PR)
                              `-> PemesananPengadaanMasterAssetDetail (PO)
                                  |-> PurchaseDeliverySchedule
                                  |-> InboundShipmentDetail
                                  `-> GoodsReceiptDetail/QC
                                      |-> PenerimaanPengadaanMasterAssetDetail (BAST supplier)
                                      `-> Putaway -> mutasi_stok

PO -> SaldoAwalMasterAsset/Tagihan Vendor -> DaftarPengajuanTransfer
                                            `-> ProsesTransfer

Shipment -> FreightOrder (opsional, bila jasa angkut eksternal)
Shipment -> DeliveryOrder -> BAST/Penerimaan Outlet -> mutasi_stok outlet
```

Prinsip kardinalitas:

- satu PR dapat menjadi beberapa PO;
- satu PO dapat memenuhi beberapa PR/permintaan outlet;
- satu PO dapat mempunyai beberapa jadwal dan receipt;
- satu receipt dapat mempunyai beberapa batch/QC disposition;
- satu invoice dapat menagih beberapa receipt dan satu receipt dapat ditagih
  bertahap;
- satu DO dapat mempunyai satu atau beberapa shipment leg;
- satu Freight Order dapat mengangkut beberapa shipment/DO jika rute konsolidasi;
- satu shipment dapat diterima parsial dan menghasilkan lebih dari satu event;
- semua relasi many-to-many penting harus memakai tabel penghubung, bukan daftar ID
  dalam `String`/JSON sebagai satu-satunya sumber kebenaran.

## 8. Gap analysis rinci

### 8.1 Gap PR/PO existing

| Gap | Risiko | Perbaikan |
|---|---|---|
| Detail hanya `MasterAsset` | Bahan/produk POS tidak dapat ditelusuri benar | Tambah catalog bridge/generic item reference. |
| Beberapa relasi/list disimpan sebagai string | Integritas referensial dan query lemah | Buat junction table terindeks; string dipertahankan sementara untuk kompatibilitas. |
| Qty/nilai banyak memakai `Double` | Rounding qty/nilai | Model baru gunakan `BigDecimal` / `numeric(18,4)` qty dan `numeric(18,2)` uang. |
| Jadwal pengiriman belum aggregate eksplisit | PO parsial sulit direncanakan | Tambah `purchase_delivery_schedule` dan detail. |
| Link kebutuhan outlet belum ada | Pengadaan tidak tahu permintaan mana yang dipenuhi | Tambah junction `procurement_demand_allocation`. |

### 8.2 Gap penerimaan/BAST supplier

| Gap | Risiko | Perbaikan |
|---|---|---|
| Penerimaan formal bercampur proses fisik | BAST dapat dianggap menambah stok dua kali | Pisahkan Goods Receipt/QC/Putaway; BAST hanya mengesahkan receipt. |
| Tidak ada batch/expiry/bin/UOM snapshot | FEFO dan audit lot hilang | Tambah detail WMS berdimensi batch/lokasi/UOM. |
| Accepted/rejected/quarantine tidak eksplisit | Stok tidak layak dapat terjual | QC disposition terstruktur dan lokasi karantina. |
| Link ledger tidak unik | Retry dapat menduplikasi stok | Unique idempotency per source document line/event. |

### 8.3 Gap tagihan

| Gap | Risiko | Perbaikan |
|---|---|---|
| Nama `SaldoAwalMasterAsset` tidak sesuai fungsi | Developer salah menggunakan tabel | Facade bisnis + dokumentasi; rencana migrasi nama/table. |
| Satu penerimaan-satu tagihan terlalu kaku | Invoice gabungan/parsial sulit | Invoice header/item + junction receipt item. |
| Matching belum eksplisit | Overbilling/duplicate invoice | Three/four-way matching dan tolerance/override audit. |
| Unique invoice vendor belum tegas | Tagihan ganda | Unique tenant/vendor/nomor invoice (normalized). |

### 8.4 Gap transfer/pengiriman

| Gap | Risiko | Perbaikan |
|---|---|---|
| `pengiriman_gudang` merangkap instruksi dan realisasi | Status dan tanggung jawab kabur | Pisahkan Transfer Order, DO, Shipment, Receipt. |
| Status string bebas | State dapat dilompati | Enum/state machine backend + history. |
| Tidak ada picking/packing/package | Tidak dapat audit short-pick atau isi paket | Tambah task dan package detail. |
| Tidak ada batch/serial/bin | Traceability hilang | Allocation dan execution per batch/bin/serial. |
| Tidak ada POD/tracking event | Sulit tahu perjalanan | Shipment event dan proof of delivery. |
| Qty/harga `Double` | Rounding | Numeric/BigDecimal pada model baru. |

### 8.5 Gap produksi

| Gap | Risiko | Perbaikan |
|---|---|---|
| `ProduksiKantin` hanya ringkasan porsi | Tidak ada nomor order/status/operator/lot | Production Order header/detail. |
| `PemakaianBahanBaku` tidak terikat BOM/order secara wajib | Pemakaian tidak dapat direkonsiliasi | BOM version + material issue line. |
| Tidak ada genealogy lot | Recall bahan ke barang jadi sulit | Link consumed batch -> produced batch. |
| Waste dan variance tidak terstruktur | HPP dan yield salah | Reason code waste, expected vs actual, approval. |

### 8.6 Gap POS dan replenishment

| Gap | Risiko | Perbaikan |
|---|---|---|
| Minimum stok belum menjadi demand terkontrol | PR/transfer ganda | Reorder rule + scheduler idempoten. |
| Penjualan dan bahan dapat diposting terpisah | Double issue/missing issue | Satu correlation ID transaksi dan atomic/outbox posting. |
| Offline sync dapat retry | Transaksi/stok ganda | Unique source transaction/detail event. |
| Stok outlet tidak membedakan reserved/quarantine | Available stock keliru | Projection `on_hand`, `reserved`, `available`, `quarantine`. |

## 9. Tabel logis baru yang disarankan

Nama final harus mengikuti konvensi migration tenant. Daftar berikut adalah model
logis, bukan perintah membuat semuanya sekaligus.

### 9.1 Demand dan replenishment

- `permintaan_stok_outlet`
- `permintaan_stok_outlet_detail`
- `reorder_rule`
- `procurement_demand_allocation`
- `reservasi_stok`
- `reservasi_stok_detail`

### 9.2 Procurement extension

- `katalog_item_pengadaan` atau bridge `pengadaan_produk_link`
- `purchase_delivery_schedule`
- `purchase_delivery_schedule_detail`
- `vendor_invoice_receipt_link` (bila facade tagihan existing diperluas)
- `invoice_match_result` dan detail

### 9.3 WMS inbound

- `inbound_shipment` dan detail
- `goods_receipt` dan detail
- `goods_receipt_qc`
- `putaway_task` dan detail

### 9.4 Distribusi outbound

- `transfer_order` dan detail
- `picking_task` dan detail
- `packing`/`packing_detail`
- `delivery_order` dan detail
- `shipment`, `shipment_package`, `shipment_event`
- `freight_order`, charge/detail, dan allocation ke shipment
- `penerimaan_outlet` dan detail
- `transfer_discrepancy`/claim/return

### 9.5 Produksi

- `bill_of_material` dan version/detail
- `production_order` dan detail
- `production_material_issue` dan detail
- `production_receipt` dan detail
- `production_waste`/variance

Model baru harus mengacu ke ledger `{S}.mutasi_stok`, bukan mempunyai kolom saldo
yang menjadi sumber kebenaran paralel.

## 10. Status minimum

| Dokumen | Status minimum |
|---|---|
| Permintaan stok | `DRAFT`, `SUBMITTED`, `APPROVED`, `ALLOCATED_PARTIAL`, `ALLOCATED`, `BACKORDER`, `FULFILLED`, `REJECTED`, `CANCELLED` |
| PR | `DRAFT`, `SUBMITTED`, `APPROVED`, `CONVERTED_PARTIAL`, `CONVERTED`, `REJECTED`, `CANCELLED` |
| PO | `DRAFT`, `APPROVED`, `SENT`, `PARTIALLY_RECEIVED`, `RECEIVED`, `CLOSED`, `CANCELLED` |
| Goods receipt | `DRAFT`, `IN_QC`, `PARTIALLY_ACCEPTED`, `POSTED`, `REJECTED`, `REVERSED` |
| Transfer order | `DRAFT`, `APPROVED`, `ALLOCATED`, `PICKING`, `PACKED`, `DISPATCHED`, `PARTIALLY_RECEIVED`, `RECEIVED`, `CANCELLED` |
| DO | `DRAFT`, `RELEASED`, `HANDED_OVER`, `DELIVERED_PARTIAL`, `DELIVERED`, `CANCELLED` |
| Shipment | `PLANNED`, `READY`, `IN_TRANSIT`, `DELAYED`, `DELIVERED_PARTIAL`, `DELIVERED`, `FAILED`, `RETURNED` |
| Penerimaan outlet | `DRAFT`, `CHECKING`, `ACCEPTED_PARTIAL`, `POSTED`, `DISPUTED`, `REVERSED` |
| Production order | `DRAFT`, `RELEASED`, `IN_PROGRESS`, `COMPLETED_PARTIAL`, `COMPLETED`, `CANCELLED`, `CLOSED` |
| Tagihan | `DRAFT`, `MATCHING`, `HOLD`, `VERIFIED`, `APPROVED`, `PARTIALLY_PAID`, `PAID`, `CANCELLED` |
| Pembayaran | `DRAFT`, `APPROVED`, `PROCESSING`, `REALIZED`, `FAILED`, `REVERSED` |

Semua transisi harus divalidasi backend, menyimpan actor/waktu/alasan, dan tidak
hanya dikendalikan UI Desktop/Android/JSP/ZK.

## 11. Aturan stok dan akuntansi

### 11.1 Kapan stok berubah

| Event | Mutasi stok |
|---|---|
| PR/PO/tagihan/pembayaran | Tidak ada |
| Goods receipt yang diposting | IN ke receiving/quarantine |
| Putaway | OUT lokasi receiving + IN lokasi storage; total gudang tetap |
| Dispatch ke outlet | OUT gudang + IN_TRANSIT |
| Penerimaan outlet diposting | OUT IN_TRANSIT + IN outlet |
| Material issue produksi | OUT bahan |
| Finished goods receipt | IN barang jadi |
| POS sale | OUT barang jadi |
| Retur/adjustment | Event khusus dengan reference dan reversal |

### 11.2 Kapan jurnal berubah

- PO: komitmen, biasanya belum jurnal finansial.
- Goods receipt: persediaan/GRNI bila kebijakan accrual.
- Invoice verified: GRNI/pajak masukan ke utang vendor.
- Payment realized: utang vendor ke kas/bank.
- Transfer internal: tidak mengubah total persediaan perusahaan; dapat mengubah
  dimensi lokasi/cost center dan biaya angkut.
- Produksi: bahan/WIP ke barang jadi dan variance/waste sesuai kebijakan.
- Penjualan POS: kas/piutang ke penjualan serta HPP ke persediaan.

## 12. Idempotensi dan konsistensi

Setiap posting wajib mempunyai key unik, misalnya:

```text
RECEIPT:{receiptDetailId}:ACCEPTED
PUTAWAY:{putawayDetailId}:MOVE
DISPATCH:{deliveryOrderDetailId}:OUT
OUTLET_RECEIPT:{penerimaanDetailId}:IN
PRODUCTION_ISSUE:{issueDetailId}:OUT
PRODUCTION_RECEIPT:{receiptDetailId}:IN
POS_SALE:{transactionCode}:{detailId}:OUT
PAYMENT:{paymentRequestId}:{attemptNo}
```

Retry API harus mengembalikan hasil yang sama. Koreksi dilakukan lewat reversal,
bukan menghapus ledger historis. Gunakan outbox/inbox untuk sinkronisasi lintas
modul dan transaksi lokal-first POS.

## 13. Rencana migrasi tanpa mematikan fungsi lama

1. Bekukan kontrak existing; jangan rename/drop tabel lama pada fase awal.
2. Tambah correlation/idempotency dan tabel mapping.
3. Buat read adapter yang menyatukan status lama dan baru.
4. Pilot satu gudang dan satu outlet dengan dual-read, bukan double-post stok.
5. Backfill referensi `Produk`/`MasterAsset` ke katalog item generik.
6. Rekonsiliasi saldo legacy dengan ledger tenant.
7. Alihkan writer per event menggunakan feature flag.
8. Setelah stabil, jadikan data lama read-only/archive; jangan hapus histori.

## 14. Fase implementasi menjadi coding

### Fase 0 — Audit produksi dan keputusan arsitektur

Pekerjaan:

- introspeksi tabel, FK, unique constraint, index, nullability, dan volume aktual;
- petakan seluruh composer/action/report yang menulis tabel existing;
- verifikasi arti `SaldoAwalMasterAsset` pada semua jalur;
- pilih ledger kanonis dan katalog item generik;
- tetapkan satuan dasar, timezone, numbering, tenant, dan gudang/outlet pilot.

Keluaran/UAT:

- ERD as-is dan to-be;
- query rekonsiliasi PR-PO-receipt-tagihan-payment;
- query rekonsiliasi saldo stok per produk/batch/lokasi;
- tidak ada migration sebelum mismatch dijelaskan.

### Fase 1 — Fondasi data dan kompatibilitas

Pekerjaan:

- buat katalog item/bridge `MasterAsset`-`Produk`;
- perkuat ledger: timestamp, UOM snapshot, unique idempotency, actor/device;
- perkuat projection saldo dan reservasi;
- buat status history dan source-document link;
- facade `TagihanVendor` atas tabel tagihan existing.

UAT:

- satu event source menghasilkan satu movement;
- rebuild saldo sama dengan projection;
- fungsi Pengadaan lama tetap lulus regresi.

### Fase 2 — Permintaan outlet dan replenishment

Pekerjaan:

- CRUD permintaan stok outlet;
- min/max/safety stock dan scheduler idempoten;
- approval, prioritas, backorder, substitusi;
- agregasi shortage menjadi usulan PR existing.

UAT:

- stok cukup menghasilkan alokasi, bukan PR;
- stok kurang menghasilkan shortage/PR tanpa duplikasi;
- pembelian lokal tunduk limit/approval.

### Fase 3 — Inbound procurement WMS

Pekerjaan:

- schedule/ASN supplier;
- receiving, QC, batch/expiry, quarantine;
- putaway dan posting ledger;
- BAST supplier mereferensikan receipt tanpa posting stok kedua.

UAT:

- partial/over/under/damaged receipt;
- retry tidak menambah stok;
- rejected stock tidak available untuk POS/produksi.

### Fase 4 — Outbound dan distribusi outlet

Pekerjaan:

- transfer order, reservation, picking, packing;
- DO, shipment, package, tracking/POD;
- Freight Order/carrier charge;
- penerimaan/BAST outlet, discrepancy, return.

UAT:

- full/partial/short/damaged/lost delivery;
- in-transit dapat direkonsiliasi;
- outlet hanya menerima item dari shipment yang sah;
- tidak ada stok negatif tanpa otorisasi.

### Fase 5 — Produksi outlet

Pekerjaan:

- BOM versioning;
- production order, reservation, issue bahan;
- hasil jadi, batch genealogy, waste/yield;
- HPP aktual/standar dan posting akuntansi.

UAT:

- expected vs actual consumption;
- partial production dan waste;
- trace bahan hingga barang jadi dan transaksi POS.

### Fase 6 — Tagihan, matching, dan pembayaran

Pekerjaan:

- three/four-way matching PO-receipt-BAST-invoice;
- invoice parsial/gabungan, DP, termin, retensi, penalti;
- integrasi pengajuan dan proses transfer existing;
- hold/override dengan approval dan audit.

UAT:

- tidak dapat menagih/mebayar melebihi sisa;
- invoice duplikat ditolak;
- payment retry tidak menghasilkan transfer ganda;
- jurnal dan saldo utang cocok.

### Fase 7 — POS dan closed-loop replenishment

Pekerjaan:

- stock issue POS idempoten;
- offline/outbox sync;
- backflush produksi bila dikonfigurasi;
- alert dan auto-replenishment dari stok minimum;
- dashboard demand, fill-rate, waste, expiry, dan stockout.

UAT:

- transaksi online/offline/retry tidak double;
- pembatalan/retur membentuk reversal yang benar;
- stok minimum memulai siklus baru tepat satu kali.

### Fase 8 — Rollout dan dekomisioning legacy

Pekerjaan:

- pilot, parallel reconciliation, observability, dan runbook;
- migrasi bertahap per tenant/gudang;
- freeze writer legacy setelah sign-off;
- archive/read-only histori dan rollback plan.

UAT akhir:

- kuantitas dokumen = ledger = saldo projection;
- nilai persediaan = subledger = jurnal;
- seluruh dokumen dapat ditelusuri dari permintaan outlet hingga POS;
- tidak ada open transaction/session leak dan tidak ada duplicate posting.

## 15. Prioritas coding yang disarankan

Urutan implementasi minimum viable tetapi aman:

1. audit schema dan writer existing;
2. catalog bridge `Produk`/`MasterAsset`;
3. ledger/idempotency/reservation;
4. permintaan stok outlet;
5. transfer order + DO + shipment + penerimaan outlet;
6. inbound receiving/QC/putaway;
7. shortage -> PR/PO existing;
8. produksi/BOM;
9. invoice matching dan termin;
10. POS closed-loop serta dashboard.

Memulai dari layar PR/PO baru tanpa fondasi item dan ledger akan menghasilkan
duplikasi data. Memulai dari ledger saja tanpa dokumen operasional juga tidak cukup.
Keduanya harus dipasang berurutan melalui adapter.

## 16. Keputusan yang masih harus dikunci pada Fase 0

- Apakah `MasterAsset` akan tetap katalog aset saja atau diperluas menjadi item
  generik? Rekomendasi: tetap aset, gunakan katalog generik/bridge.
- Apakah tagihan baru langsung memakai tabel generik atau facade tabel existing?
  Rekomendasi: facade dahulu, migrasi sesudah variasi invoice teruji.
- Kapan ownership stok berpindah: dispatch atau receipt outlet? Rekomendasi:
  gunakan status IN_TRANSIT dan ownership policy eksplisit.
- Apakah gudang utama satu legal entity dengan outlet? Ini menentukan jurnal
  transfer internal versus intercompany.
- Apakah barang siap saji make-to-stock atau make-to-order? Ini menentukan
  production order versus POS backflush.
- Apakah FO diperlukan untuk semua DO atau hanya carrier eksternal? Rekomendasi:
  opsional; DO tetap dapat dikirim armada sendiri tanpa FO.

## 17. Definition of Done lintas modul

Implementasi belum dianggap selesai hanya karena layar CRUD tersedia. Selesai bila:

- semua foreign key sumber dapat ditelusuri dari permintaan hingga penjualan;
- semua movement mempunyai source, correlation, idempotency, actor, dan timestamp;
- status tidak dapat dilompati dari client;
- qty dan nilai memakai presisi yang benar;
- partial, cancellation, return, reversal, dan retry diuji;
- stok, in-transit, produksi, utang, pembayaran, dan jurnal direkonsiliasi;
- seluruh `openSession()`/native session ditutup pada `finally`, sedangkan
  `currentSession()` tidak ditutup manual;
- backend tetap kompatibel Java 1.7/gaya Java 1.6;
- perubahan Desktop, Android, JSP, dan ZK memakai kontrak API/backend yang sama;
- dokumentasi migration, UAT, rollback, SVN revision, dan Git commit dicatat pada
  folder `docs/pos`.

## 18. Jawaban langsung atas pertanyaan tabel terpisah

**Jangan mengganti seluruh tabel Pengadaan existing dengan tabel Pergudangan baru.**
Pertahankan PR, PO, BAST supplier, tagihan, dan pembayaran untuk workflow external
yang sudah berjalan. Tambahkan adapter item agar `Produk` dapat masuk tanpa
menyalahgunakan `MasterAsset`.

**Buat tabel terpisah untuk permintaan stok outlet, reservation/allocation,
Transfer Order, Delivery Order, Freight Order, Shipment, penerimaan/BAST outlet,
dan produksi.** Dokumen-dokumen ini berbeda secara tanggung jawab, kardinalitas,
status, dan dampak stok. Pisah tabel bukan berarti terputus: semuanya wajib
terhubung dengan foreign key/junction table dan satu ledger stok kanonis.

**PO termin dan nontermin tidak perlu dipisahkan.** Gunakan satu PO dengan schedule
termin/DP/milestone. Existing sudah mempunyai fondasi `byTermin`, `poInduk`,
`PembayaranDpMasterAsset*`, dan `PembayaranTerminMasterAsset*`.

Desain ini paling aman untuk mempertahankan fungsi lama sekaligus memungkinkan
rantai tertutup: permintaan outlet -> pemenuhan/pengadaan -> pengiriman ->
penerimaan -> produksi -> POS -> replenishment ulang.
