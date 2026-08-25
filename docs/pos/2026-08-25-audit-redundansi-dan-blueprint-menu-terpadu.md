# Audit redundansi dan blueprint menu terpadu eBisnis

Tanggal audit: 25 Agustus 2026  
Status: rancangan final sebelum perubahan menu runtime  
Ruang lingkup: POS Desktop, Android, JSP, ZKoss, API eBisnis, `TbmroleAction`, Pengadaan, Pergudangan, Distribusi, Produksi, Keuangan, dan Akuntansi.

## 1. Tujuan

Dokumen ini menjadi peta implementasi utama untuk merapikan menu tanpa:

1. membuat dua menu untuk satu proses bisnis;
2. memutus fungsi lama yang sudah dipakai pengguna;
3. menghapus kunci hak akses lama secara mendadak;
4. mencatat stok atau jurnal dua kali;
5. mencampur dokumen pengadaan vendor dengan perpindahan internal gudang-outlet;
6. membuat perilaku berbeda antara Desktop, Android, JSP, dan ZKoss.

Dokumen ini melengkapi, bukan menggantikan:

- `2026-08-25-rancangan-terpadu-pengadaan-pergudangan-distribusi-produksi-pos.md`;
- `2026-08-25-arsitektur-menu-rantai-pasok.md`;
- `2026-08-25-fase-implementasi-menu-dan-hak-akses-rantai-pasok.md`;
- `2026-08-25-gap-struktur-tabel-pergudangan.md`.

## 2. Sumber audit

Audit tidak hanya berdasarkan tangkapan layar. Struktur berikut juga diperiksa:

1. menu aktif Desktop pada `apps/ebisnis/lib/widgets/app_shell.dart`;
2. menu alternatif/legacy pada `apps/ebisnis/lib/widgets/app_drawer.dart`;
3. katalog izin server pada `ais.common.EbisnisMenuKatalog`;
4. layar `Jenis Produk`, `Grup Produk`, `Kulakan`, dan `Barang Dalam Proses`;
5. hubungan BAST dengan sinkronisasi ke stok Kulakan;
6. konsolidasi Pembayaran Vendor dan Transitori ke layar Proses Transfer;
7. dokumen analisis Pengadaan, Pergudangan, Pengiriman, Produksi, Keuangan, dan Akuntansi yang sudah ada.

## 3. Prinsip keputusan

### 3.1 Satu use case, satu pemilik kanonik

Setiap proses hanya boleh mempunyai satu route, satu service penulis, dan satu sumber status kanonik. Menu lain hanya boleh menjadi:

- shortcut yang membuka route kanonik;
- tab dengan izin tambahan;
- widget ringkasan baca-saja;
- tautan laporan.

Shortcut tidak boleh mempunyai penyimpanan, state machine, atau API mutasi sendiri.

### 3.2 Nama mirip belum tentu duplikat

Menu tidak boleh digabung hanya karena istilahnya mirip. Contoh:

- `Pesanan` adalah pesanan/keranjang pelanggan, bukan Purchase Order;
- `Jenis Produk` menentukan klasifikasi dan akun, sedangkan `Grup Produk` mengatur HPP, resep, harga, serta rule lintas toko;
- `Kulakan` adalah transaksi pembelian langsung, sedangkan `Posting Kulakan` adalah proses akuntansi;
- BAST vendor berbeda dari bukti penerimaan transfer oleh outlet.

### 3.3 Pindah menu tidak berarti mengganti kunci izin

ID/kunci izin lama dipertahankan pada tahap migrasi. Label dan grup boleh berubah, tetapi `TbmroleAction` tetap menjadi otoritas. Alias dicatat pada registry menu supaya pengguna lama tidak kehilangan akses.

### 3.4 Satu kejadian stok, satu ledger event

PR, PO, BAST, invoice, DO, shipment, penerimaan outlet, produksi, dan POS boleh saling merujuk, tetapi perubahan stok hanya dilakukan oleh event persediaan kanonik. Setiap event wajib mempunyai idempotency key dan referensi dokumen asal.

### 3.5 Transaksi, posting, dan laporan dipisahkan

- transaksi mengubah state bisnis;
- posting membentuk jurnal akuntansi;
- laporan hanya membaca data.

Tiga fungsi tersebut tidak boleh disatukan hanya untuk mengurangi jumlah menu.

## 4. Temuan utama audit existing

### 4.1 Tumpang tindih struktur, bukan selalu tumpang tindih fungsi

Masalah terbesar menu existing adalah penempatan:

- `Stok Opname`, `Kedaluwarsa`, dan `Mutasi Antar Outlet` diletakkan di **Master Data**, padahal merupakan proses operasional persediaan;
- `Kulakan` juga berada di **Master Data**, padahal merupakan transaksi pembelian langsung;
- `Terima Tagihan Vendor` tampil di **Pengadaan**, padahal pemilik kanonik invoice/AP seharusnya **Keuangan**;
- `Barang Dalam Proses` saat ini mencampur monitor barang belum datang dan konsep CIP/barang dalam penyelesaian;
- penerimaan BAST dapat disinkronkan ke Kulakan, sehingga tanpa kontrak idempotensi pengguna dapat menganggapnya dua transaksi terpisah.

### 4.2 Konsolidasi yang sudah benar dan harus dipertahankan

Layar `Proses Transfer` sudah mengonsolidasikan:

- transfer umum;
- pembayaran vendor;
- transitori.

Kunci izin lama tetap dipakai sebagai izin tab. Ini pola migrasi yang benar: satu workspace kanonik, izin granular tetap tersedia.

### 4.3 Izin Kedaluwarsa masih menumpang pada Stok Opname

Menu Kedaluwarsa saat ini menggunakan izin `stokopname`. Ini perlu dipisah bertahap menjadi izin khusus batch/kedaluwarsa, dengan fallback ke izin lama selama masa kompatibilitas.

### 4.4 BAST ke Kulakan adalah jembatan stok

BAST approved belum otomatis berarti stok operasional bertambah. Existing menyediakan sinkronisasi satu kali ke Kulakan. Arsitektur target tidak boleh mempertahankan dua transaksi yang bisa diedit independen; jembatan ini harus menjadi penerbit event penerimaan stok yang idempoten dengan referensi BAST.

## 5. Matriks keputusan menu existing

| Grup existing | Menu existing | Keputusan | Nama/lokasi target | Alasan dan batas fungsi |
|---|---|---|---|---|
| Operasional | Kasir/POS | Pertahankan | Operasional Penjualan > Kasir/POS | Entry penjualan dan pembayaran pelanggan. |
| Operasional | Pesanan | Pertahankan | Operasional Penjualan > Pesanan Pelanggan | Bukan PR/PO; mencakup order online/tertahan/pending. |
| Operasional | Layar Pelanggan | Pertahankan | Operasional Penjualan > Layar Pelanggan | Customer display, bukan transaksi baru. |
| Dashboard | Dashboard | Pertahankan | Dashboard / Control Tower | Ringkasan baca-saja dan drill-down. |
| Master Data | Pelanggan | Pertahankan | Master Data > Pelanggan/Member | Entitas pelanggan lintas POS. |
| Master Data | Produk | Pertahankan | Master Data > Produk | SKU/barcode/item master. |
| Master Data | Jenis Produk | Pertahankan dan perjelas | Master Data > Kategori Produk & Akun | Kategori serta mapping akun penjualan, pajak, dan HPP; bukan grup harga. |
| Master Data | Grup Produk | Pertahankan dan perjelas | Master Data > Grup Harga, HPP & Resep | Rule lintas toko, resep, HPP, harga, dan diskon; bukan kategori akuntansi. |
| Master Data | Stok Opname | Pindahkan | Pergudangan > Pengendalian Persediaan > Stok Opname | Proses operasional stok, bukan master. |
| Master Data | Kedaluwarsa | Pindahkan | Pergudangan > Batch, FEFO & Kedaluwarsa | Operasional lot/batch/quality. |
| Master Data | Mutasi Antar Outlet | Konsolidasikan | Distribusi > Transfer Antar Lokasi | Menjadi aggregate transfer/DO/shipment; route lama menjadi alias. |
| Master Data | Kulakan | Pindahkan dan batasi | Pengadaan > Pembelian Langsung (Kulakan) | Jalur pembelian langsung tanpa PR/PO; tidak menggandakan BAST enterprise. |
| Master Data | Supplier (Penyedia) | Pertahankan | Master Data > Mitra Bisnis > Supplier/Vendor | Master vendor untuk Kulakan dan Pengadaan. |
| Master Data | Aturan Diskon | Pertahankan | Master Data > Aturan Komersial > Diskon & Promo | Rule penjualan, bukan Akuntansi. |
| Master Data | Cara Pembayaran | Pertahankan | Master Data > Aturan Komersial > Cara Pembayaran | Master tender/metode pembayaran. |
| Pengadaan | Permintaan Pembelian (PR) | Pertahankan | Pengadaan > Permintaan Pembelian (PR) | Kebutuhan beli eksternal, bukan permintaan stok outlet. |
| Pengadaan | Pemesanan Pembelian (PO) | Pertahankan | Pengadaan > Purchase Order / Kontrak | Mendukung termin/nontermin sebagai atribut/term, bukan dua menu. |
| Pengadaan | Penerimaan Barang (BAST) | Pertahankan dan perjelas | Pengadaan > Penerimaan Vendor (BAST) | Bukti penerimaan dari vendor; berbeda dari penerimaan transfer outlet. |
| Pengadaan | Terima Tagihan Vendor | Jadikan shortcut/status | Keuangan > Utang Usaha > Tagihan Vendor | AP adalah pemilik invoice dan 3-way match. Pengadaan hanya menampilkan status. |
| Pengadaan | Barang Dalam Proses | Pecah semantik | Pengadaan > Monitoring Pengadaan; Akuntansi/Aset > CIP bila relevan | `Belum Datang` adalah monitor PO/shipment; CIP adalah aset/barang dalam penyelesaian. |
| Keuangan | Uang Muka | Pertahankan | Keuangan > Uang Muka | Cash advance tersendiri. |
| Keuangan | Pertanggungjawaban Uang Muka | Pertahankan sebagai pasangan | Keuangan > Uang Muka > Pertanggungjawaban | Settlement, bukan duplikasi uang muka. |
| Keuangan | Kas Besar | Pertahankan | Keuangan > Kas Besar | Transaksi kas besar. |
| Keuangan | Pertanggungjawaban Kas Besar | Pertahankan sebagai pasangan | Keuangan > Kas Besar > Pertanggungjawaban | Settlement. |
| Keuangan | Kas Kecil | Pertahankan | Keuangan > Kas Kecil | Petty cash. |
| Keuangan | Replacement Kas Kecil | Pertahankan sebagai aksi/tab | Keuangan > Kas Kecil > Replenishment | Lebih tepat tab/aksi dari workspace Kas Kecil. |
| Keuangan | Dana Talangan | Pertahankan | Keuangan > Dana Talangan | Piutang sementara kepada pihak yang menalangi. |
| Keuangan | Reimbursement | Pertahankan | Keuangan > Reimbursement | Penggantian biaya, bukan uang muka. |
| Keuangan | Proses Transfer | Pertahankan sebagai workspace kanonik | Keuangan > Pembayaran & Transfer | Sudah mengonsolidasikan vendor/transitori dengan izin tab. |
| Keuangan | Pembayaran Vendor | Jangan buat layar kedua | Keuangan > Pembayaran & Transfer > tab Vendor | Akses lewat workspace kanonik. |
| Keuangan | Transitori | Jangan buat layar kedua | Keuangan > Pembayaran & Transfer > tab Transitori | Akses lewat workspace kanonik. |
| Akuntansi | Kode/Grup Akun | Pertahankan | Akuntansi > Bagan Akun | Master COA. |
| Akuntansi | Draft/Jurnal Umum | Pertahankan | Akuntansi > Jurnal | Draft dan posted state satu domain. |
| Akuntansi | Posting Penjualan/HPP/Kulakan/Pembayaran | Pertahankan sebagai job akuntansi | Akuntansi > Posting Otomatis | Bukan duplikasi transaksi asal. |
| Akuntansi | Saldo Awal/Penyesuaian/Tutup Buku | Pertahankan | Akuntansi > Period End | Proses akuntansi. |
| Laporan | Riwayat Penjualan | Pertahankan | Laporan > Penjualan > Riwayat | Baca/drill-down, bukan Kasir. |
| Laporan | Laporan Transaksi | Pertahankan | Laporan > Penjualan > Laporan Transaksi | Analitik dan ekspor. |
| Laporan | Laporan-Laporan/Katalog | Konsolidasikan | Laporan > Katalog Laporan | Satu katalog, kategori sebagai filter. |

## 6. Menu yang tampak sama tetapi wajib tetap terpisah

### 6.1 Jenis Produk dan Grup Produk

`Jenis Produk` adalah klasifikasi akuntansi dan pajak. `Grup Produk` adalah pengelompokan komersial/operasional yang dapat membawa harga, HPP, resep, serta aturan lintas toko. Keduanya boleh berelasi, tetapi tidak boleh dilebur menjadi satu tabel atau satu izin.

### 6.2 Pesanan, PR, dan permintaan stok outlet

- Pesanan: demand pelanggan.
- Permintaan stok outlet: demand internal antar lokasi.
- PR: permintaan pembelian kepada vendor.

Ketiganya mempunyai pihak, persetujuan, SLA, dan dampak stok berbeda.

### 6.3 Penerimaan Vendor dan Penerimaan Outlet

- BAST Vendor menyelesaikan penerimaan terhadap PO/vendor.
- Penerimaan Outlet/POD menyelesaikan transfer internal terhadap DO/shipment.

Nama dokumen outlet boleh berupa berita acara penerimaan, tetapi entity dan nomor referensinya tidak boleh memakai BAST vendor.

### 6.4 Kulakan dan Posting Kulakan

Kulakan mengubah persediaan/utang atau kas. Posting Kulakan membentuk jurnal dari transaksi yang sudah terjadi. Tombol posting dapat ditampilkan pada workspace akuntansi, bukan sebagai jalur pembelian kedua.

### 6.5 Retur Pembelian, Retur Transfer, dan Retur Penjualan

Ketiganya harus terpisah karena lawan transaksi dan reversal ledger berbeda:

- retur pembelian ke vendor;
- retur transfer dari outlet ke gudang/pengirim;
- retur penjualan dari pelanggan.

## 7. Pohon menu target

### 7.1 Operasional Penjualan

1. Kasir/POS
2. Pesanan Pelanggan
3. Layar Pelanggan
4. Retur Penjualan

### 7.2 Dashboard & Control Tower

1. Dashboard Bisnis
2. Control Tower Rantai Pasok
3. Alert & Pengecualian
4. KPI dan SLA

### 7.3 Master Data

1. Pelanggan/Member
2. Produk
3. Kategori Produk & Akun
4. Grup Harga, HPP & Resep
5. Satuan/UOM dan Konversi
6. Supplier/Vendor
7. Outlet, Gudang, Zona, dan Bin
8. Armada dan Ekspedisi
9. Aturan Diskon/Promo
10. Cara Pembayaran

### 7.4 Perencanaan & Replenishment

1. Kebijakan Min-Max/Reorder Point
2. Permintaan Stok Outlet
3. Konsolidasi Kebutuhan
4. Rekomendasi Replenishment
5. Alokasi Stok

### 7.5 Pengadaan

1. Permintaan Pembelian (PR)
2. Permintaan Penawaran/RFQ dan Seleksi Vendor
3. Purchase Order/Perjanjian
4. Pembelian Langsung (Kulakan)
5. Penerimaan Vendor (BAST)
6. Monitoring Pengadaan
7. Retur Pembelian
8. Status Tagihan Vendor (shortcut baca-saja)

Termin/nontermin menjadi `payment_term`, jadwal pembayaran, dan milestone pada PO/invoice. Jangan dibuat sebagai dua menu PO.

### 7.6 Pergudangan

1. Dashboard Gudang
2. Jadwal Inbound
3. Penerimaan Fisik & Quality Check
4. Putaway
5. Persediaan per Gudang/Zona/Bin
6. Batch, FEFO, Kedaluwarsa & Karantina
7. Reservasi & Alokasi
8. Picking
9. Packing
10. Stok Opname/Cycle Count
11. Penyesuaian Stok
12. Retur Gudang

### 7.7 Distribusi & Pengiriman

1. Transfer Antar Lokasi
2. Delivery Order
3. Freight Order/Rute/Muatan
4. Shipment & Tracking
5. Proof of Delivery
6. Penerimaan Transfer Outlet
7. Selisih/Kerusakan/Klaim
8. Retur dan Reverse Logistics

### 7.8 Produksi

1. Formula/BOM/Resep
2. Rencana Produksi
3. Work/Production Order
4. Material Issue
5. Work in Process
6. Hasil Produksi/Finished Goods
7. Waste/Yield/Selisih

### 7.9 Keuangan

1. Utang Usaha
   - Tagihan Vendor
   - 3-Way Match PO-BAST-Invoice
   - Jadwal/Termin Pembayaran
   - Pembayaran Vendor
2. Piutang Usaha
3. Uang Muka dan Pertanggungjawaban
4. Kas Besar
5. Kas Kecil dan Replenishment
6. Dana Talangan
7. Reimbursement
8. Pembayaran & Transfer
9. Pajak

### 7.10 Akuntansi

1. Bagan Akun
2. Jenis Transaksi
3. Draft Jurnal
4. Jurnal Umum
5. Posting Otomatis
   - Penjualan
   - HPP
   - Kulakan/Pembelian
   - Pembayaran Utang
   - Penerimaan Piutang
   - Produksi dan Selisih Stok
6. Saldo Awal
7. Penyesuaian
8. Tutup Buku

### 7.11 Laporan

1. Penjualan
2. Pengadaan
3. Persediaan/Pergudangan
4. Distribusi/Pengiriman
5. Produksi
6. Keuangan
7. Akuntansi
8. Audit Trail

### 7.12 Sistem

1. Konfigurasi
2. Hak Akses
3. Riwayat Sinkronisasi
4. Log Error
5. Audit Aktivitas

## 8. Kontrak route dan hak akses anti-duplikasi

### 8.1 Registry kanonik

Setiap menu perlu satu record registry dengan atribut minimum:

- `menu_key` stabil;
- `canonical_route`;
- `parent_key`;
- `sort_order`;
- `platforms`;
- `legacy_aliases`;
- `required_actions`;
- `feature_flag`;
- `deprecated_since`;
- `replacement_key`.

### 8.2 Aturan `TbmroleAction`

1. `TbmroleAction` tetap sumber izin utama.
2. `Common.apakahAdmin() == true` boleh melihat dan mengakses semua menu, tetapi mutasi berisiko tetap diaudit.
3. Izin menu tidak otomatis memberi izin approve/post/cancel/export.
4. Alias lama diperiksa bila izin baru belum tersedia.
5. Setelah migrasi role terverifikasi, alias baru boleh ditandai deprecated; jangan langsung dihapus.

### 8.3 Aksi granular minimum

Setiap domain transaksional minimal membedakan:

- `VIEW`;
- `CREATE`;
- `EDIT_DRAFT`;
- `SUBMIT`;
- `APPROVE`;
- `REJECT`;
- `CANCEL`;
- `POST`;
- `REVERSE`;
- `EXPORT`;
- `VIEW_COST`;
- `VIEW_ALL_LOCATION`.

## 9. Dependensi antarmodul

```text
Master Data
    |
    v
Perencanaan/Replenishment -----> Permintaan Stok Outlet
    |                                  |
    | stok kurang                      | stok tersedia
    v                                  v
Pengadaan -> PO -> BAST Vendor -> Inbound/Putaway
    |                                  |
    v                                  v
Tagihan/AP -> Pembayaran          Inventory Available
                                       |
                                       v
                              DO -> Picking -> Packing
                                       |
                                       v
                              Shipment -> POD Outlet
                                       |
                                       v
                              Produksi -> Barang Jadi
                                       |
                                       v
                                     POS
                                       |
                                       v
                              Replenishment berulang
```

Setiap panah adalah referensi dokumen, bukan izin untuk menulis ulang data dokumen sebelumnya.

## 10. Fase implementasi sangat rinci

### Fase 0 — Baseline, inventaris, dan freeze kontrak

Tujuan: mengetahui seluruh permukaan existing sebelum memindahkan menu.

Pekerjaan:

1. ekspor seluruh menu dari Desktop, Android, JSP, ZKoss, dan server catalog;
2. petakan `menu_key`, route, endpoint, controller, tabel, role action, serta platform;
3. tandai route yang menulis stok, kas, utang, dan jurnal;
4. rekam snapshot jumlah role dan izin existing;
5. buat UAT golden flow untuk POS, Kulakan, PR-PO-BAST, transfer, pembayaran, dan posting;
6. bekukan penambahan menu baru di luar registry selama refactor.

Artefak:

- `menu-inventory.csv`;
- matriks menu-route-API-table-role;
- daftar mutation writer;
- baseline screenshot dan API contract.

Gerbang lulus:

- 100% menu terlihat dalam inventaris;
- tidak ada endpoint mutasi tanpa pemilik domain;
- golden flow existing dapat diulang.

### Fase 1 — Registry menu kanonik dan alias legacy

Tujuan: satu definisi menu digunakan lintas platform.

Pekerjaan:

1. perluas `EbisnisMenuKatalog` atau buat registry kanonik terstruktur;
2. tetapkan parent, urutan, route, label, ikon, feature flag, dan alias;
3. tambahkan validator duplikasi route dan `menu_key` pada build/test;
4. tambahkan API `menu_context` yang mengembalikan menu sesuai izin;
5. jangan hapus key existing.

Gerbang lulus:

- satu `menu_key` hanya mempunyai satu canonical route;
- semua alias menunjuk target yang valid;
- snapshot menu lintas platform identik secara semantik.

### Fase 2 — Fondasi otorisasi dan migrasi `TbmroleAction`

Tujuan: perpindahan menu tidak mengubah hak pengguna.

Pekerjaan:

1. tambahkan aksi granular;
2. buat mapping old-key ke canonical-key;
3. seed permission baru secara idempoten;
4. salin izin role lama ke izin canonical tanpa menghapus sumber;
5. implementasikan bypass admin resmi;
6. catat audit saat admin menjalankan aksi berisiko;
7. sediakan laporan perbandingan izin sebelum/sesudah.

Gerbang lulus:

- nol role kehilangan menu yang sebelumnya dapat diakses;
- non-admin tidak memperoleh aksi tambahan;
- admin dapat melihat semua menu pada seluruh platform;
- semua approve/post/reverse tercatat.

### Fase 3 — Reorganisasi informasi tanpa mengubah proses bisnis

Tujuan: memperbaiki sidebar dahulu dengan risiko minimal.

Pekerjaan:

1. pindahkan Stok Opname dan Kedaluwarsa ke Pergudangan;
2. pindahkan Kulakan ke Pengadaan;
3. pindahkan Mutasi ke Distribusi;
4. ubah Terima Tagihan Pengadaan menjadi shortcut ke AP;
5. pertahankan route lama sebagai alias;
6. perbarui bantuan kontekstual dan breadcrumb;
7. gunakan accordion/collapsible group agar sidebar tidak terlalu panjang.

Gerbang lulus:

- route lama tetap terbuka;
- tidak ada menu ganda pada sidebar;
- tidak ada perubahan payload API atau hasil transaksi.

### Fase 4 — Klarifikasi Master Data

Tujuan: menghilangkan kebingungan Jenis vs Grup dan menyiapkan WMS.

Pekerjaan:

1. ubah label Jenis Produk menjadi Kategori Produk & Akun;
2. ubah label Grup Produk menjadi Grup Harga, HPP & Resep;
3. tambahkan UOM dan konversi;
4. tambah master gudang, zona, bin, dock, armada, ekspedisi;
5. dokumentasikan ownership setiap field;
6. migrasi UI Desktop, Android, JSP, ZKoss.

Gerbang lulus:

- mapping akun existing tidak berubah;
- harga/HPP/resep existing tidak berubah;
- master lokasi tervalidasi unik per tenant/toko.

### Fase 5 — Konsolidasi Pengadaan

Tujuan: menyediakan jalur direct purchase dan enterprise procurement tanpa double receipt.

Pekerjaan:

1. tetapkan PR, PO, BAST Vendor sebagai dokumen kanonik;
2. simpan termin/nontermin sebagai payment terms/milestone;
3. pertahankan Kulakan untuk direct purchase;
4. ubah sinkron BAST-ke-Kulakan menjadi service penerimaan stok idempoten;
5. simpan `source_document_type`, `source_document_id`, dan idempotency key;
6. pastikan BAST yang sama tidak dapat menambah stok dua kali;
7. pecah monitor `Belum Datang` dari konsep CIP;
8. tambahkan retur pembelian dengan reversal event.

Gerbang lulus:

- direct purchase dan PO purchase menghasilkan ledger yang setara secara prinsip;
- satu BAST hanya menghasilkan satu penerimaan;
- pembatalan/reversal dapat ditelusuri;
- total PO, BAST, invoice dapat direkonsiliasi.

### Fase 6 — Perencanaan dan permintaan outlet

Tujuan: membedakan demand internal dari PR vendor.

Pekerjaan:

1. kebijakan min/max/ROP per produk-lokasi;
2. permintaan stok outlet manual/otomatis;
3. konsolidasi kebutuhan beberapa outlet;
4. availability check gudang;
5. split ke alokasi gudang atau PR vendor;
6. SLA dan approval permintaan.

Gerbang lulus:

- permintaan stok tidak membuat PR jika stok gudang cukup;
- shortage dapat membuat draft PR dengan traceability;
- satu kebutuhan tidak dipenuhi dua kali.

### Fase 7 — WMS inbound

Tujuan: memisahkan penerimaan administratif dari eksekusi gudang.

Pekerjaan:

1. appointment/jadwal inbound;
2. receiving line terhadap BAST/PO;
3. QC, lot, expiry, serial, damage, quarantine;
4. putaway task ke bin;
5. status received, quality hold, putaway, available;
6. event ledger ketika stok layak tersedia.

Gerbang lulus:

- stok tidak available sebelum QC/putaway sesuai konfigurasi;
- selisih kuantitas tercatat;
- batch dan expiry dapat ditelusuri ke vendor dan BAST.

### Fase 8 — Pengendalian persediaan

Tujuan: menyatukan operasi stok internal di bawah Pergudangan.

Pekerjaan:

1. stok per lokasi/bin/batch;
2. reservasi dan alokasi;
3. cycle count/stok opname;
4. expiry/FEFO dan karantina;
5. adjustment dengan approval;
6. stock ledger drill-down;
7. migrasi izin Kedaluwarsa dari fallback `stokopname` ke key khusus.

Gerbang lulus:

- saldo = opening + seluruh event ledger;
- tidak ada stok negatif tanpa kebijakan eksplisit;
- semua adjustment mempunyai alasan dan approver.

### Fase 9 — Outbound, distribusi, dan pengiriman

Tujuan: mengembangkan Mutasi Antar Outlet tanpa membuat modul paralel.

Pekerjaan:

1. jadikan mutasi existing aggregate transfer canonical;
2. buat DO dari alokasi;
3. picking dan packing;
4. FO/rute/muatan;
5. shipment, tracking, handover;
6. POD dan penerimaan outlet;
7. selisih, kerusakan, klaim, reverse logistics;
8. route Mutasi lama menjadi alias ke workspace baru.

Gerbang lulus:

- stok asal berkurang dan in-transit bertambah pada event yang disepakati;
- stok tujuan bertambah hanya setelah penerimaan;
- partial shipment/receipt didukung;
- satu DO tidak dapat dikirim atau diterima ganda.

### Fase 10 — Produksi outlet/gudang

Tujuan: mengubah bahan baku/setengah jadi menjadi barang siap jual.

Pekerjaan:

1. BOM/resep berversi;
2. production order;
3. issue bahan berdasarkan FEFO;
4. WIP;
5. finished goods receipt;
6. waste/yield/by-product;
7. costing dan posting HPP produksi;
8. release barang jadi ke POS.

Gerbang lulus:

- konsumsi bahan dan hasil jadi seimbang sesuai toleransi;
- versi resep yang digunakan tersimpan;
- POS hanya menjual stok released.

### Fase 11 — AP, pembayaran, dan Akuntansi

Tujuan: satu alur finansial dari PO sampai pembayaran dan jurnal.

Pekerjaan:

1. pindahkan ownership Terima Tagihan ke AP;
2. 2-way/3-way match;
3. invoice, pajak, retensi, dan termin;
4. jadwal pembayaran;
5. pembayaran lewat Proses Transfer tab Vendor;
6. posting pembelian, stok, utang, pembayaran, produksi, selisih;
7. reversal dan period lock.

Gerbang lulus:

- invoice tidak dapat dibayar dua kali;
- unmatched invoice memerlukan exception approval;
- subledger AP cocok dengan GL;
- posting idempoten dan dapat direversal.

### Fase 12 — Laporan dan Control Tower

Tujuan: satu katalog laporan dengan drill-down, bukan menu laporan yang berulang.

Pekerjaan:

1. konsolidasikan katalog laporan;
2. kategori sebagai tab/filter;
3. KPI pengadaan, inbound, inventory, outbound, produksi, AP;
4. exception queue;
5. drill-down sampai dokumen dan ledger event;
6. ekspor PDF/Excel/Word sesuai hak akses.

Gerbang lulus:

- angka dashboard dapat direkonsiliasi dengan transaksi sumber;
- filter tenant/toko/gudang konsisten;
- laporan tidak menjalankan mutation.

### Fase 13 — Paritas Desktop, Android, JSP, dan ZKoss

Tujuan: kontrak sama, presentasi adaptif.

Pekerjaan:

1. gunakan registry dan permission API yang sama;
2. buat contract test untuk route/payload/status;
3. samakan empty/loading/error/success states;
4. Desktop dan Android mendukung offline sesuai domain yang diizinkan;
5. JSP/ZKoss tetap dapat menggunakan key legacy selama masa transisi;
6. uji role snapshot lintas platform.

Gerbang lulus:

- proses yang sama menghasilkan state server yang sama;
- tidak ada menu tanpa implementasi;
- tidak ada platform yang bypass izin.

### Fase 14 — Migrasi data, UAT end-to-end, dan rollout

Tujuan: beralih tanpa menghentikan operasi.

Pekerjaan:

1. migration dry-run dan checksum;
2. backfill external reference/idempotency key;
3. parallel-read, single-write;
4. UAT skenario stok cukup, stok kurang, pembelian lokal, partial receipt, partial shipment, retur, produksi, POS, pembayaran;
5. pilot satu gudang dan satu outlet;
6. observability dan reconciliation dashboard;
7. rollback plan;
8. deprecate alias setelah dua siklus audit sukses.

Gerbang lulus:

- nol double stock event;
- nol double invoice/payment;
- semua role lulus UAT;
- saldo stok, AP, kas/bank, dan GL direkonsiliasi;
- rollback teruji.

## 11. Urutan coding per fase

Untuk setiap fase, urutan kerja wajib:

1. kontrak domain dan status;
2. migration/schema idempoten;
3. model/entity dan repository;
4. service kanonik;
5. API dan error contract;
6. permission seed/migration;
7. Desktop;
8. Android;
9. JSP;
10. ZKoss;
11. automated test;
12. UAT data nyata;
13. dokumentasi `/docs/pos/`;
14. commit SVN server terlebih dahulu bila server berubah;
15. commit/push Git client setelah UAT.

UI tidak boleh dibuat sebelum service kanonik dan idempotensi ditetapkan untuk proses yang mengubah stok/uang.

## 12. Definition of Done anti-redundansi

Sebuah menu/modul dianggap selesai hanya bila:

1. mempunyai satu canonical route;
2. route lama terdokumentasi sebagai alias atau sudah didekomisioning;
3. tidak ada dua mutation writer untuk event bisnis yang sama;
4. `TbmroleAction` dan admin behavior lulus UAT;
5. Desktop, Android, JSP, dan ZKoss mempunyai kontrak yang sama;
6. seluruh tombol approve/post/reverse mempunyai audit trail;
7. stok dan jurnal tidak dicatat dua kali;
8. laporan dapat ditelusuri ke dokumen sumber;
9. bantuan kontekstual menjelaskan batas fungsi;
10. perubahan dicatat di `/docs/pos/`.

## 13. Keputusan yang harus dikunci sebelum coding Fase 5+

1. apakah BAST existing hanya untuk asset atau juga legal dipakai untuk produk persediaan;
2. titik event stok untuk vendor receiving: saat BAST, QC, atau putaway;
3. kapan transfer memindahkan stok ke status in-transit;
4. apakah penerimaan outlet membutuhkan approval/BA tersendiri;
5. ownership costing produksi dan metode valuasi;
6. toleransi 3-way match;
7. scope tenant/toko/gudang untuk role;
8. masa kompatibilitas alias menu dan key izin lama.

## 14. Rekomendasi eksekutif

Tidak perlu membuat ulang seluruh menu dari nol. Struktur existing dapat dipertahankan dengan empat tindakan utama:

1. **pindahkan** proses stok dari Master Data ke Pergudangan;
2. **konsolidasikan** Mutasi Antar Outlet menjadi Transfer/Distribusi dan Terima Tagihan menjadi AP;
3. **perjelas** Jenis Produk, Grup Produk, BAST Vendor, Kulakan, dan Barang Dalam Proses;
4. **pertahankan** key izin lama sebagai alias sampai migrasi `TbmroleAction` dan UAT lintas platform selesai.

Pekerjaan pertama yang aman adalah Fase 0 sampai Fase 3. Implementasi tabel dan mutasi stok baru baru dimulai setelah registry menu, ownership domain, serta aturan idempotensi lulus review.
