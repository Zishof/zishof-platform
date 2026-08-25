# Arsitektur menu Rantai Pasok, Pergudangan, Distribusi, Produksi, dan POS

Tanggal: 25 Agustus 2026  
Status: Rekomendasi arsitektur informasi sebelum implementasi UI

Dokumen ini menurunkan rancangan terpadu pada
`2026-08-25-rancangan-terpadu-pengadaan-pergudangan-distribusi-produksi-pos.md`
menjadi struktur menu yang dapat diimplementasikan. Tujuannya adalah menutup alur
permintaan outlet sampai penjualan POS tanpa menggandakan fungsi Pengadaan,
Keuangan, dan Akuntansi yang sudah ada.

## 1. Keputusan utama

Menu baru yang paling tepat bukan sekadar satu menu `Pergudangan`. Kebutuhan
end-to-end memerlukan enam kapabilitas operasional:

1. Perencanaan Persediaan dan Replenishment;
2. Pergudangan;
3. Distribusi dan Pengiriman;
4. Produksi;
5. Mutu dan Ketertelusuran;
6. Kendali Rantai Pasok.

Agar sidebar tidak terlalu panjang, keenam kapabilitas tersebut disarankan berada
di dalam satu kelompok navigasi **Rantai Pasok**. `Pengadaan`, `Keuangan`,
`Akuntansi`, dan `POS` tetap menjadi modul existing. Menu baru hanya menautkan
dokumen dan status dari modul existing, bukan membuat PR, PO, tagihan,
pembayaran, jurnal, atau transaksi penjualan versi kedua.

Struktur tingkat atas yang disarankan:

```text
RANTAI PASOK
|- Kendali Rantai Pasok
|- Perencanaan & Replenishment
|- Pengadaan                         [existing]
|- Pergudangan                       [baru]
|- Distribusi & Pengiriman           [baru]
|- Produksi                          [baru]
`- Mutu & Ketertelusuran             [baru/bertahap]

PENJUALAN & OUTLET
|- Operasional Outlet                [workspace berbasis peran]
`- POS/Kasir                         [existing]

KEUANGAN
|- Tagihan Vendor                    [existing/diperjelas]
|- Pembayaran                        [existing]
`- Akuntansi                         [existing]
```

`Operasional Outlet` bukan domain data baru. Ia adalah workspace ringkas yang
menampilkan layar-layar relevan bagi outlet dari Replenishment, Distribusi,
Pergudangan, Produksi, dan POS. Satu layar yang sama dapat memiliki lebih dari
satu pintasan menu, tetapi harus memakai service, route, dan tabel yang sama.

## 2. Menu yang tetap dipertahankan

| Menu existing | Keputusan | Penambahan yang diperlukan |
|---|---|---|
| Pengadaan | Pertahankan | Tautkan shortage/replenishment ke PR; generic item bridge untuk Produk; jadwal pengiriman PO; status penerimaan WMS. |
| Keuangan | Pertahankan | Tampilkan invoice/tagihan vendor, matching PO-receipt-invoice, hold/dispute, dan status pembayaran. |
| Akuntansi | Pertahankan | Posting persediaan, barang dalam perjalanan, produksi, HPP, variance, dan pembalikan idempoten. |
| POS/Kasir | Pertahankan | Stock issue idempoten, pilihan lot FEFO bila relevan, dan pemicu replenishment setelah stok minimum. |
| Master Data | Pertahankan dan perluas | Item supply chain, UOM, gudang/lokasi/bin, batch, carrier, rute, BOM/resep, kebijakan reorder. |
| Laporan | Pertahankan dan perluas | Laporan lintas modul; jangan membuat sumber angka baru di dashboard. |

## 3. Menu Perencanaan & Replenishment

Menu ini menutup kebutuhan sebelum PR atau transfer gudang dibuat. Permintaan
stok internal tidak boleh langsung dianggap sebagai PR pembelian vendor.

```text
Perencanaan & Replenishment
|- Dashboard Kebutuhan Stok
|- Permintaan Stok Outlet
|  |- Draft Saya
|  |- Menunggu Persetujuan
|  |- Sedang Dipenuhi
|  `- Selesai / Dibatalkan
|- Usulan Replenishment Otomatis
|- Alokasi & Reservasi Stok
|- Kekurangan / Backorder
|- Substitusi Barang
|- Pembelian Lokal Outlet
|- Kebijakan Min-Max & Reorder Point
|- Forecast Kebutuhan
`- Riwayat Pemenuhan
```

Fungsi penting:

- menggabungkan permintaan outlet agar tidak menjadi banyak PR kecil;
- menentukan `stok tersedia -> transfer` dan `stok kurang -> shortage/PR`;
- mencegah reservasi, transfer, atau PR ganda dengan idempotency key;
- mengelola pembelian lokal sebagai pengecualian yang tetap diaudit;
- memperlihatkan jumlah diminta, dialokasi, dikirim, diterima, backorder, dan
  dibatalkan dalam satu alur.

## 4. Menu Pergudangan

```text
Pergudangan
|- Dashboard Gudang
|- Penerimaan Barang
|  |- Jadwal Kedatangan / ASN
|  |- Goods Receipt
|  |- Pemeriksaan & QC
|  `- Putaway
|- Persediaan
|  |- Posisi Stok per Gudang/Lokasi
|  |- Available, Reserved, Quarantine, In Transit
|  |- Batch / Lot / Kedaluwarsa
|  |- Kartu Stok / Ledger Mutasi
|  `- Aging Persediaan
|- Alokasi & Reservasi
|- Picking
|- Packing
|- Goods Issue / Serah ke Pengiriman
|- Transfer Antar Lokasi Gudang
|- Stok Opname & Cycle Count
|- Penyesuaian Stok
|- Karantina & Release
|- Retur ke Vendor
|- Barang Rusak / Hilang / Disposal
`- Rekonsiliasi Persediaan
```

Batas tanggung jawab:

- PR dan PO tetap di Pengadaan;
- tagihan dan pembayaran tetap di Keuangan;
- Pergudangan mengelola kejadian fisik: receive, QC, putaway, reserve, pick,
  pack, issue, count, dan adjustment;
- BAST supplier dapat mengesahkan Goods Receipt, tetapi tidak boleh membuat
  posting stok kedua;
- semua perubahan stok masuk ke ledger kanonik `{S}.mutasi_stok` secara
  idempoten.

## 5. Menu Distribusi & Pengiriman

```text
Distribusi & Pengiriman
|- Dashboard Distribusi
|- Rencana Distribusi
|- Transfer Order
|- Delivery Order / Surat Jalan
|- Konsolidasi Muatan
|- Freight Order
|- Shipment
|  |- Penjadwalan
|  |- Paket / Koli
|  |- Kendaraan, Pengemudi, Carrier
|  |- Tracking Event
|  `- Proof of Delivery
|- Monitoring Barang Dalam Perjalanan
|- Penerimaan Outlet / BAST Internal
|- Selisih, Rusak, dan Kekurangan Kirim
|- Retur Outlet ke Gudang
|- Gagal Kirim / Pengiriman Ulang
|- Tarif, SLA, dan Tagihan Angkutan
`- Riwayat & Kinerja Pengiriman
```

Dokumen harus tetap terpisah secara semantik:

- Transfer Order adalah instruksi pemindahan stok;
- Delivery Order adalah dokumen barang/surat jalan;
- Shipment adalah eksekusi perjalanan;
- Freight Order adalah pesanan jasa angkut;
- BAST Outlet adalah pengakuan penerimaan transfer internal.

Satu shipment dapat membawa beberapa DO dan satu Freight Order dapat membiayai
beberapa shipment, selama relasinya eksplisit.

## 6. Menu Produksi

```text
Produksi
|- Dashboard Produksi
|- Master BOM / Resep
|- Versi Resep & Konversi UOM
|- Rencana Produksi
|- Production Order
|- Kebutuhan & Reservasi Bahan
|- Pengeluaran Bahan
|- Work in Process
|- Penerimaan Barang Jadi
|- Hasil, Yield, Waste, dan Variance
|- Rework / Produk Gagal
|- Label Batch Produksi
|- Penutupan Order Produksi
`- Riwayat & Traceability Produksi
```

Produksi mengubah bahan baku atau barang setengah jadi menjadi barang jadi.
`koperasi.produksi_kantin` dan `koperasi.pemakaian_bahan_baku` dapat dipertahankan
sebagai data legacy, tetapi order, issue bahan, receipt hasil, lot genealogy,
yield, dan waste memerlukan transaksi produksi yang eksplisit.

## 7. Menu Mutu & Ketertelusuran

Pada fase awal, submenu ini boleh tampil di bawah Pergudangan. Ketika penggunaan
bertambah, ia dapat menjadi modul tingkat atas tanpa mengubah model data.

```text
Mutu & Ketertelusuran
|- Antrian QC Inbound
|- Sampling & Hasil Pemeriksaan
|- Karantina / Release / Reject
|- Non-Conformance
|- Corrective & Preventive Action
|- Batch, Lot, dan Kedaluwarsa
|- FEFO dan Peringatan Kedaluwarsa
|- Traceability Supplier -> Outlet -> POS
|- Recall Produk
|- Cold Chain / Kondisi Pengiriman
`- Audit Mutu
```

Menu ini penting untuk bahan pangan, produk jadi, dan obat. Pengguna harus dapat
menelusuri lot dari penerimaan supplier, perpindahan gudang, produksi, pengiriman,
penerimaan outlet, sampai transaksi POS.

## 8. Menu Kendali Rantai Pasok

Ini adalah control tower, bukan penyimpan transaksi baru.

```text
Kendali Rantai Pasok
|- Ringkasan End-to-End
|- Permintaan & Shortage
|- PO dan Kedatangan Terlambat
|- Kapasitas & Beban Gudang
|- Stok Kritis / Overstock / Slow Moving
|- Barang Dalam Perjalanan
|- Kinerja Pemenuhan Outlet
|- Kinerja Supplier
|- Kinerja Carrier & OTIF
|- Yield & Waste Produksi
|- Exception Center
|- Rekonsiliasi Stok dan Finansial
`- Audit Trail Dokumen
```

KPI minimum:

- fill rate permintaan outlet;
- stockout, backorder, dan lead time replenishment;
- PO on-time delivery;
- dock-to-stock dan picking accuracy;
- OTIF pengiriman;
- selisih kirim/terima;
- inventory accuracy dan aging;
- yield, waste, dan variance produksi;
- nilai stok, in-transit, committed, dan available.

Semua angka harus dapat dibuka ke rincian dokumen sumber.

## 9. Workspace Operasional Outlet

Untuk petugas outlet, menu rantai pasok lengkap terlalu besar. Berikan workspace
berbasis peran berikut:

```text
Operasional Outlet
|- Ringkasan Stok Outlet
|- Buat Permintaan Barang
|- Status Permintaan
|- Barang Akan Datang
|- Terima Barang / BAST Outlet
|- Laporkan Selisih atau Kerusakan
|- Retur ke Gudang
|- Pembelian Lokal
|- Produksi Outlet
|- Stok Minimum & Kedaluwarsa
`- Buka POS/Kasir
```

Workspace ini menggunakan dokumen yang sama dengan modul pusat. Jangan membuat
tabel `permintaan_outlet_mobile`, `bast_outlet_pos`, atau transaksi duplikat lain.

## 10. Perluasan Master Data

Letakkan di menu Master Data existing:

```text
Master Data
|- Katalog Item Rantai Pasok
|- Relasi Produk - MasterAsset - Item Pengadaan
|- Jenis Barang: Bahan Baku / Setengah Jadi / Jadi / Aset / Jasa
|- Satuan & Konversi UOM
|- Gudang, Zona, Lokasi, Bin
|- Batch / Lot Policy
|- Supplier & Kontrak
|- Carrier, Kendaraan, Pengemudi
|- Rute & Service Level
|- BOM / Resep
|- Kebijakan Reorder
|- Alasan Adjustment / Reject / Return
`- Matriks Approval
```

Katalog bridge menjadi syarat sebelum transaksi Produk dimasukkan ke workflow
PR/PO existing yang saat ini berorientasi `MasterAsset`.

## 11. Hak akses dan visibilitas menu

| Peran | Menu utama yang terlihat |
|---|---|
| Outlet/Kasir | Operasional Outlet, POS, penerimaan yang ditugaskan, retur sendiri |
| Supervisor Outlet | Seluruh workspace outlet, approval permintaan lokal, produksi outlet, rekonsiliasi outlet |
| Planner | Kendali Rantai Pasok, Replenishment, forecast, allocation |
| Procurement | Pengadaan, shortage yang perlu dibeli, supplier performance |
| Petugas Gudang | Pergudangan sesuai gudang yang ditugaskan |
| Supervisor Gudang | Seluruh Pergudangan, approval adjustment, rekonsiliasi |
| QC | QC, karantina, release, non-conformance, recall |
| Dispatcher/Logistik | Distribusi, DO, shipment, tracking, POD |
| Produksi | Production Order, issue bahan, receipt hasil, yield/waste |
| Keuangan/AP | Tagihan, matching, hold, pengajuan pembayaran |
| Akuntansi | Posting, rekonsiliasi, reversal, laporan |
| Auditor/Admin | Read-only lintas modul, audit trail; mutasi sesuai otorisasi eksplisit |

Menu tidak cukup hanya disembunyikan di UI. Setiap API dan aksi harus memeriksa
tenant, toko/gudang, peran, status dokumen, serta batas otorisasi.

## 12. Pemetaan delapan langkah bisnis ke menu

| Langkah bisnis | Menu utama |
|---|---|
| Outlet meminta barang habis | Operasional Outlet -> Buat Permintaan Barang |
| Outlet membeli bahan khusus dari vendor lokal | Replenishment -> Pembelian Lokal Outlet, lalu Pengadaan existing |
| Gudang menilai ketersediaan | Replenishment -> Alokasi & Reservasi |
| Kekurangan gudang dibeli dari vendor | Pengadaan existing: PR -> PO -> BAST; Keuangan: tagihan -> pembayaran |
| Barang ready dan dikirim | Pergudangan: picking/packing/issue; Distribusi: TO/DO/FO/shipment |
| Outlet menerima barang | Operasional Outlet -> Terima Barang / BAST Internal |
| Outlet memproduksi barang siap saji | Produksi -> Production Order -> issue bahan -> receipt barang jadi |
| Barang dijual dan stok minimum memicu siklus ulang | POS existing -> stock issue -> Replenishment |

## 13. Prioritas implementasi menu

### Fase menu 1 — Operasional inti

1. Perencanaan & Replenishment;
2. Pergudangan: receiving, QC, putaway, inventory, picking, packing, issue;
3. Distribusi: TO, DO, shipment, penerimaan outlet;
4. Workspace Operasional Outlet;
5. badge status dan exception dasar.

### Fase menu 2 — Produksi dan mutu

1. BOM/resep dan Production Order;
2. material issue, receipt hasil, yield/waste;
3. batch/expiry, quarantine/release, traceability dan recall.

### Fase menu 3 — Kendali dan optimasi

1. Control tower end-to-end;
2. forecast, auto-replenishment, route/load consolidation;
3. carrier SLA, freight charge, advanced reconciliation;
4. analitik supplier, gudang, distribusi, dan produksi.

## 14. Aturan UX agar menu tidak membengkak

- Sidebar hanya menampilkan menu sesuai peran dan lokasi kerja pengguna.
- Gunakan kelompok yang dapat dilipat: Rantai Pasok, Penjualan & Outlet,
  Keuangan, Master Data, dan Sistem.
- Dashboard menampilkan `Perlu tindakan saya`, bukan seluruh dokumen.
- Gunakan badge jumlah untuk `Menunggu approval`, `Backorder`, `QC`,
  `Siap dikirim`, `Dalam perjalanan`, `Selisih`, dan `Jatuh tempo`.
- Sediakan pencarian menu/command palette dan favorit untuk pengguna power-user.
- Daftar memakai filter tersimpan, pagination server-side, dan lazy loading.
- Detail dokumen memperlihatkan timeline end-to-end dan tautan dokumen asal/
  turunannya: permintaan -> alokasi -> PR/PO -> receipt -> DO/shipment -> BAST
  outlet -> produksi -> POS.
- Jangan membuat screen baru hanya untuk status; gunakan satu daftar dengan view
  tersimpan bila perilaku dan datanya sama.

## 15. Rekomendasi akhir

Menu tambahan yang **wajib** dibuat untuk memenuhi kebutuhan minimum adalah:

1. `Perencanaan & Replenishment`;
2. `Pergudangan`;
3. `Distribusi & Pengiriman`;
4. `Produksi`;
5. `Operasional Outlet` sebagai workspace berbasis peran.

Menu yang **penting tetapi dapat diluncurkan bertahap** adalah:

6. `Mutu & Ketertelusuran`;
7. `Kendali Rantai Pasok`.

Master data supply chain, laporan, konfigurasi workflow, hak akses, dan audit
ditambahkan ke modul existing. Dengan pembagian ini, kebutuhan operasional
tertutup lengkap tanpa membangun ulang Pengadaan, Keuangan, Akuntansi, atau POS.

