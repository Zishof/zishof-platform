# PERINTAH MASTER CODEX / CLAUDE CODE
## MEMBANGUN VARIAN FLUTTER **eBisnis POS INVENTORY & SALES**
### Server Java AIS + Paritas 48 Layar + Surat Perintah Sales Jalan + Nota Sales

> Dokumen ini adalah instruksi eksekusi. Jangan berhenti pada analisis, mockup, skeleton, TODO, atau daftar rencana. Audit source nyata terlebih dahulu, lalu implementasikan secara incremental dengan build, test, bukti, dan commit.

---

# 0. IDENTITAS PEKERJAAN

## 0.1 Workspace dan repository

### Flutter

```text
Workspace lokal : C:\opt\CodeBaseDesktopDanMobile\
Repository      : https://github.com/Zishof/zishof-platform
Produk existing : apps/ebisnis
Target baru     : varian inventory_sales dari aplikasi existing, bukan copy-paste aplikasi kedua
```

### Server Java

```text
Repository      : https://github.com/Zishof/AIS.git
Branch pada screenshot pengguna:
feat/new-ui-rbac-role-user
Workspace yang diperkirakan:
C:\opt\AIS\ais\src\main
```

Branch, commit, remote, dan path WAJIB diverifikasi pada komputer lokal. Jangan menganggap screenshot sebagai pengganti `git status`, `git branch --show-current`, `git remote -v`, dan `git rev-parse HEAD`.

## 0.2 Bahan wajib

Cari, hash, dan baca sampai selesai:

1. `Panduan-Transisi-48-Layar-eBisnis-Inventory-Sales-v2-Paritas-Fungsional.pdf`;
2. file analisis video/48 frame yang telah dibuat;
3. video `Sistem Sales.mp4` bila tersedia lokal;
4. repository `Zishof/zishof-platform`;
5. repository `Zishof/AIS`;
6. source legacy/DBF bila tersedia;
7. seluruh migration, entity, API, JSP/ZK, Flutter, test, CI, release, dan dokumentasi terkait POS, inventory, koperasi, kantin, supplier, customer, sales, kas, jurnal, dan laporan.

Buat:

```text
docs/pos-inventory-sales/source-manifest.sha256
docs/pos-inventory-sales/source-inventory.md
docs/pos-inventory-sales/assumption-register.md
docs/pos-inventory-sales/uat-required.md
```

## 0.3 Klasifikasi kebenaran

Setiap keputusan diberi label:

- `FACT_SOURCE`: terbukti dari source;
- `FACT_MANUAL`: terbukti dari panduan, screenshot, atau video;
- `STRONG_INFERENCE`: didukung beberapa bukti tetapi belum diamati runtime;
- `DESIGN_DECISION`: target modern yang disetujui;
- `UAT_REQUIRED`: membutuhkan keputusan pengguna lama/pemilik bisnis.

Jangan mengarang endpoint, tabel, field, atau status sebagai seolah-olah sudah ada. Bila source dan dokumen berbeda, catat drift dan pilih solusi kompatibel.

---

# 1. MISI AKHIR

Bangun varian Flutter baru bernama:

```text
Kode varian : inventory_sales
Nama produk : eBisnis Inventory & Sales
Windows     : eBisnis-Inventory-Sales-Setup-<versi>.exe
Android     : eBisnis-Inventory-Sales-<versi>.apk / .aab
```

Varian baru harus:

1. menggunakan server Java AIS yang sama;
2. memanfaatkan API `/Api_eBisnis`;
3. menggabungkan fungsi POS existing dengan seluruh fungsi 48 layar legacy;
4. memakai UI modern responsif untuk Windows dan Android;
5. mendukung semi-online/offline-first;
6. mempertahankan Admin existing;
7. menambah Pemilik Sales/Inventory;
8. menambah Sales Keliling;
9. memakai Kulakan sebagai basis Pembelian Supplier;
10. menambah Penjualan Sales, Surat Perintah Sales Jalan, Nota Sales, biaya perjalanan, collection, pembelian selama perjalanan, rekonsiliasi barang, dan laporan satu sesi;
11. tidak memecah sumber kebenaran stok, uang, customer, supplier, produk, role, atau user;
12. mempunyai bukti paritas tersendiri untuk setiap 48 layar.

---

# 2. LARANGAN KERAS

Jangan:

- membuat backend Node/Nest baru;
- membuat database kedua;
- membuat salinan penuh `apps/ebisnis` dengan kode yang langsung divergen;
- menulis ulang POS existing dari nol;
- memindahkan aturan bisnis ke Flutter;
- hard-code role berdasarkan teks label di banyak tempat;
- menganggap user tanpa Toko otomatis Admin;
- memodifikasi transaksi posted;
- menghapus histori pembayaran, hutang, piutang, stok, atau jurnal;
- memakai `double` untuk logika uang server baru;
- memakai Java 8 lambda, stream, Optional, record, `var`, switch expression, atau API modern yang tidak kompatibel Java 1.7;
- menjalankan `DROP DATABASE`, `DROP SCHEMA ... CASCADE`, reset migration, atau mengubah migration yang sudah diterapkan;
- menimpa `.env`, konfigurasi production, signing key, atau data lokal;
- membuat tombol “Segera Hadir” untuk requirement yang dinyatakan selesai;
- memakai data hard-coded sebagai pengganti API;
- mengklaim build/test/commit/push berhasil bila belum dijalankan;
- force-push atau reset hard atas pekerjaan pengguna;
- menggabungkan role aktif dengan union privilege. Gunakan role aktif existing.

---

# 3. HASIL AUDIT SOURCE YANG HARUS DIVERIFIKASI ULANG

## 3.1 Flutter existing yang harus direuse

Audit menunjukkan `apps/ebisnis` sudah mempunyai komponen nyata:

- `KasirScreen`;
- `KeranjangScreen`;
- `PesananScreen`;
- `AnggotaScreen`;
- `ProdukScreen`;
- `StokOpnameScreen`;
- `MutasiAntarOutletScreen`;
- `KulakanScreen`;
- `ReturPembelianTab`;
- `ReturPenjualanScreen`;
- `RiwayatPenjualanScreen`;
- `LaporanTransaksiScreen`;
- `LaporanScreen`;
- `HakAksesScreen`;
- `AppShell`, `AppDrawer`, responsive breakpoint;
- `ApiClient`;
- `CoreDb`;
- scanner kamera melalui `core_hw`;
- PDF/printing;
- multi-window pelanggan.

Jangan menduplikasi komponen pencarian produk, format rupiah, app shell, autentikasi, server config, printer, scanner, maupun mekanisme update.

## 3.2 Modul Kulakan

`KulakanScreen` sudah mempunyai:

- nomor faktur;
- tanggal faktur;
- pilihan supplier;
- banyak baris produk;
- scan barcode;
- qty;
- harga beli;
- total manual/potongan;
- riwayat faktur;
- detail faktur;
- retur pembelian.

Gunakan ini sebagai dasar layar legacy nomor 20. Perluas, jangan ganti total.

## 3.3 Offline existing

`CoreDb` telah mempunyai SQLite, cache produk/member, transaksi pending, cache referensi, error log, dan sesi kas. Namun kompleksitas Nota Sales membutuhkan schema local baru dan outbox command yang typed. `core_sync` dan sebagian package core lain harus diaudit karena dapat masih berupa placeholder.

## 3.4 Server AIS

`ApiEBisnis` saat ini merupakan alias bermerek yang mewarisi `PosApi`. Seluruh aksi baru khusus Sales/Inventory harus ditempatkan pada jalur eBisnis, tetapi jangan menggandakan autentikasi, CORS, parsing JSON, atau response normalization.

Refactor aman yang direkomendasikan:

```java
// PosApi.java
protected boolean prosesAksiTambahan(
        String action,
        Tbmuser user,
        JSONObject payload,
        JSONObject hasil,
        HttpServletRequest request,
        HttpServletResponse response) throws Exception {
    return false;
}
```

Panggil hook tersebut sebelum “aksi tidak dikenal”. Override pada `ApiEBisnis`, lalu delegasikan ke:

```text
ais.action.servlet.api.SalesInventoryApiDispatcher
ais.action.servlet.api.SalesInventoryHelper
```

Jangan memindahkan atau mengubah perilaku aksi POS lama.

## 3.5 Risiko keamanan konteks user

Konfigurasi existing harus diaudit karena konteks Toko sering berasal dari `Tbmuser.getPedagang()`. User Sales baru dapat tidak mempunyai Pedagang. Jangan pernah menyimpulkan:

```text
toko == null => Admin
```

Buat resolver fail-closed:

```text
EbisnisActorContextResolver
- user
- role aktif
- isAdmin sebenarnya
- Toko aktif
- Pedagang bila ada
- SalesInventory bila ada
- scope tenant/toko
- permission map
```

User tanpa scope yang sah ditolak; bukan dinaikkan menjadi Admin.

---

# 4. STRATEGI VARIAN BUILD TANPA DUPLIKASI

## 4.1 Product profile

Refactor bootstrap agar dua entrypoint memakai kode bersama:

```text
lib/bootstrap.dart
lib/product_profile.dart
lib/main.dart
lib/main_inventory_sales.dart
```

Contoh:

```dart
Future<void> main() async {
  await bootstrap(const AppProductProfile.ebisnis());
}
```

```dart
Future<void> main() async {
  await bootstrap(const AppProductProfile.inventorySales());
}
```

`AppProductProfile` minimal memuat:

- code;
- app name;
- sidebar name;
- logo;
- theme seed;
- update asset keyword;
- enabled feature groups;
- default landing by actor;
- desktop binary/product metadata;
- Android flavor metadata.

Jangan membuat cabang `if (variant == ...)` tersebar di puluhan layar. Gunakan feature profile dan permission service.

## 4.2 Windows

Tambahkan dukungan `inventory_sales` pada:

- `windows/variant.cmake`;
- runner CMake;
- `Runner.rc`;
- icon/resource;
- installer Inno Setup;
- build script;
- CI matrix.

Ketentuan:

- AppId installer unik dan permanen;
- nama executable/produk unik;
- folder instalasi unik;
- update keyword unik;
- tidak menimpa eBisnis POS default atau Al-Bahjah;
- Windows 10/11 x64;
- bundle VC++ runtime seperti existing;
- signed release bila certificate tersedia;
- checksum SHA-256.

## 4.3 Android

Tambahkan product flavor tanpa merusak build existing:

```gradle
flavorDimensions "product"
productFlavors {
    ebisnis {
        dimension "product"
        applicationId "id.zishof.ebisnis"
    }
    inventorySales {
        dimension "product"
        applicationId "id.zishof.ebisnis.inventorysales"
        resValue "string", "app_name", "eBisnis Inventory & Sales"
    }
}
```

Sesuaikan dengan struktur Gradle aktual. Buat source set icon/name. Release tidak boleh memakai debug signing. Tambahkan wrapper build agar developer tidak lupa flavor.

Perintah target:

```powershell
cd C:\opt\CodeBaseDesktopDanMobile
fvm use
cd apps\ebisnis

fvm flutter pub get
fvm flutter analyze
fvm flutter test

fvm flutter run -d windows -t lib/main_inventory_sales.dart `
  --dart-define=EBISNIS_VARIANT=inventory_sales

fvm flutter build windows --release `
  -t lib/main_inventory_sales.dart `
  --dart-define=EBISNIS_VARIANT=inventory_sales

fvm flutter build apk --release `
  --flavor inventorySales `
  -t lib/main_inventory_sales.dart `
  --dart-define=EBISNIS_VARIANT=inventory_sales

fvm flutter build appbundle --release `
  --flavor inventorySales `
  -t lib/main_inventory_sales.dart `
  --dart-define=EBISNIS_VARIANT=inventory_sales
```

Gunakan Flutter/FVM version yang dipatok repository. Jangan upgrade dependency massal dalam pekerjaan ini.

---

# 5. PENGGUNA, ROLE, DAN HAK AKSES

## 5.1 Tiga jenis pengguna bisnis

### A. Admin

Pertahankan seluruh perilaku existing. Jangan mengurangi hak dan jangan mengubah landing page tanpa konfigurasi.

### B. Pemilik Sales/Inventory

Seed idempotent role:

```text
roleId   : pemilik_sales_inventory
roleName : Pemilik Sales / Inventory
```

Hak minimal:

- seluruh 48 layar sesuai scope toko;
- master supplier/customer/sales/produk;
- harga beli/jual;
- pembelian, hutang, pembayaran;
- penjualan, piutang, collection;
- stok, opname, transfer, batch/expiry;
- membuat, mengubah, submit, approve, membatalkan Surat Perintah Sales Jalan;
- memilih banyak nota;
- memilih barang;
- mengatur uang muka;
- melihat biaya;
- approve/reject biaya;
- rekonsiliasi dan menutup sesi;
- kas/jurnal/laba rugi;
- print/export/audit dan data sensitif sesuai privilege.

### C. Sales Keliling

Seed idempotent role:

```text
roleId   : sales_keliling
roleName : Sales Keliling
```

Hak minimal dalam scope tugasnya:

- lihat profil sendiri;
- lihat customer, produk, harga, dan stok yang diizinkan;
- lihat Surat Perintah milik sendiri;
- mulai sesi;
- lihat barang dan nota yang ditugaskan;
- input Sales Order;
- ubah status pesan/siap kirim/terkirim;
- input penerimaan piutang penuh/sebagian;
- input hasil gagal tagih/janji bayar;
- input biaya;
- input pembelian supplier cash/DP/kredit;
- upload bukti;
- lihat ringkasan sesi sendiri;
- cetak/share bukti sesuai izin;
- return session.

Sales dilarang:

- mengubah master global;
- mengubah harga pokok;
- mengubah invoice posted;
- memilih invoice di luar assignment;
- menyetujui SPJ sendiri;
- menutup sesi final sendiri bila ada selisih;
- melihat laba seluruh perusahaan;
- melihat rekening sensitif tanpa privilege;
- menghapus biaya/collection yang telah tersinkron; gunakan reversal request.

## 5.2 Integrasi RBAC existing

1. Tambahkan key menu baru ke `EbisnisMenuKatalog`.
2. Tambahkan CRUD/aksi granular.
3. Seed role melalui helper idempotent mengikuti pola `MenuHelper`.
4. Hubungkan role ke menu/privilege existing.
5. `Tbmuser` tetap mendukung multi-role.
6. Role aktif berasal dari `Tbmuser.hakAkses()` dan switcher existing.
7. Privilege tidak di-union.
8. Server selalu memeriksa privilege; Flutter hanya menyembunyikan/disable UI.
9. Response konfigurasi mengirim:
   - `actorType`;
   - `activeRoleId`;
   - `roleIds`;
   - `salesId`;
   - `salesName`;
   - `tokoId`;
   - `permissions`;
   - `currentTripId`;
   - `featureProfile`.

Kunci menu rekomendasi:

```text
master_supplier
master_customer
master_sales
persediaan
stok_opname
harga
kulakan
hutang
sales_order
penjualan_sales
piutang
surat_perintah_sales
nota_sales
biaya_sales
pembelian_sales
rekonsiliasi_sales
kas_jurnal
laba_rugi
laporan_inventory_sales
```

Aksi granular tambahan:

```text
view
create
update
deactivate
assign
submit
approve
reject
dispatch
post
cancel
reverse
collect
expense
purchase
reconcile
close
print
export
audit
view_sensitive
```

---

# 6. MODEL DOMAIN DAN ERD

Baca dokumen pendamping:

```text
ERD_DAN_SPESIFIKASI_DATA_NOTA_SALES_JAVA_AIS.md
```

Entity minimum:

```text
SalesInventory
SuratPerintahSalesJalan
SuratPerintahSalesJalanBarang
SuratPerintahSalesJalanNota
NotaSalesSession
SalesOrderLapangan
SalesOrderLapanganItem
NotaSalesPenerimaan
NotaSalesPenerimaanAlokasi
KategoriBiayaSales
NotaSalesBiaya
NotaSalesPembelian
NotaSalesKas
NotaSalesLampiran
NotaSalesStatusLog
```

Audit entity existing sebelum membuat:

```text
CustomerInventoryProfile
SupplierInventoryProfile
ReceivableDocument
PayableDocument
PurchaseDocument
```

Jika existing sudah setara, gunakan adapter/link; jangan buat duplikat.

## 6.1 Relasi Sales dan Tbmuser

`SalesInventory` adalah entity baru yang menghubungkan:

```text
SalesInventory -> Tbmuser
SalesInventory -> Toko
SalesInventory -> Tbmrole melalui role user, bukan FK langsung
```

Satu akun dapat mempunyai multi-role, tetapi satu profil sales aktif per toko. Sales dapat dinonaktifkan tanpa menghapus histori.

## 6.2 Customer dan supplier

- Customer: audit `AnggotaKoperasi`, profil member, alamat, limit kredit, dan transaksi existing. Bila identitas dapat direuse tetapi field sales tidak ada, buat `CustomerInventoryProfile` one-to-one/one-to-many sesuai toko.
- Supplier: audit `PemasokProduk`, `Penyedia`, pengadaan, dan Kulakan. Bila perlu, buat `SupplierInventoryProfile`.
- Jangan menyamakan member retail dengan customer distributor tanpa field profile dan aturan eksplisit.

## 6.3 Istilah existing yang membingungkan

Pada AIS, nama `DraftPembelian` dapat berarti pembelian customer terhadap toko, yaitu sisi **penjualan toko**. Jangan menganggap semua class bernama Pembelian sebagai supplier procurement. Buat mapping istilah:

```text
Legacy/UI “Penjualan”        -> transaksi customer membeli dari toko
Existing DraftPembelian      -> kemungkinan baris draft sale/customer order
UI “Kulakan/Pembelian Supplier” -> procurement dari supplier
```

Dokumentasikan keputusan entity mapping sebelum coding.

---

# 7. SURAT PERINTAH SALES JALAN

## 7.1 Form header

Field wajib:

- nomor otomatis;
- Toko/tenant;
- Sales;
- tanggal berangkat rencana;
- jam berangkat;
- rute/area;
- kendaraan;
- pengemudi bila berbeda;
- uang muka operasional;
- catatan;
- status;
- pembuat;
- approver;
- attachment;
- local draft ID;
- server reference;
- sync status.

Nomor tidak boleh dapat diedit setelah issued.

## 7.2 Detail barang dibawa

Bulk picker search-first:

- produk;
- kode/barcode;
- kategori;
- stok gudang;
- stok tersedia;
- batch;
- expiry;
- satuan;
- qty rencana;
- qty dimuat;
- HPP snapshot;
- harga default;
- lokasi asal;
- tujuan stok mobil.

Validasi:

- tidak boleh melebihi stok tersedia tanpa approval;
- batch/expiry wajib bila product tracking aktif;
- movement stok dibuat saat `DISPATCHED`, bukan saat draft;
- retry idempotent;
- barang tidak hilang ketika perangkat offline;
- return/terjual/rusak/hilang harus direkonsiliasi.

## 7.3 Detail nota/piutang dibawa

Buat picker setara pola AmbilDataBanyak tetapi melalui API search+paging:

Filter:

- customer;
- nomor invoice;
- sales;
- jatuh tempo;
- aging;
- area;
- status;
- nilai minimum/maksimum;
- belum pernah assigned;
- assignment sebelumnya selesai.

Tabel:

- checkbox;
- invoice;
- customer;
- tanggal;
- jatuh tempo;
- saldo;
- aging;
- sales;
- status;
- last collection;
- catatan.

Operasi:

- pilih halaman;
- pilih semua hasil filter dengan token selection server;
- exclude item tertentu;
- tambah ke SPJ secara batch;
- cegah assignment ganda;
- snapshot saldo pada saat assignment;
- tampilkan perubahan saldo sebelum dispatch.

## 7.4 Cetak

PDF Surat Perintah memuat:

- nomor;
- sales;
- tanggal/rute;
- uang muka;
- daftar barang;
- daftar invoice;
- total nilai barang;
- total nilai piutang;
- signature owner, gudang, sales;
- QR/checksum;
- versi dan waktu;
- alasan reprint.

---

# 8. PENJUALAN SALES LAPANGAN

Tambahkan tombol/menu:

```text
Penjualan Sales
```

Gunakan komponen produk/customer/keranjang existing, tetapi workflow berbeda dari Kasir instan.

## 8.1 Pemilihan customer

Search by:

- kode;
- nama;
- telepon;
- alamat;
- area;
- recent;
- assigned customer.

Tampilkan:

- termin;
- limit kredit;
- saldo piutang;
- overdue;
- harga khusus;
- sales owner;
- blacklist/hold;
- last order.

## 8.2 Status

```text
DRAFT/PESAN
CONFIRMED
READY_TO_DELIVER
DELIVERED
INVOICED
READY_TO_COLLECT
PARTIAL_PAID
PAID
OVERDUE
CANCELLED
RETURNED
```

Ketentuan:

- `PESAN` belum mengurangi stok final;
- reservation harus eksplisit;
- `DELIVERED` mencatat barang, batch, lokasi, penerima, bukti;
- `INVOICED` membentuk piutang dan HPP snapshot;
- `PARTIAL_PAID/PAID` berasal dari alokasi collection, bukan edit status manual;
- posted invoice tidak dihapus;
- cancellation/reversal membutuhkan alasan dan privilege.

## 8.3 UI

Desktop:

- 3-pane: customer, search product/order lines, sticky summary;
- keyboard shortcuts;
- barcode USB;
- table lebar.

Android:

- wizard/card:
  1. Customer;
  2. Produk;
  3. Keranjang;
  4. Pengiriman/termin;
  5. Review;
- scan kamera;
- autosave draft;
- status sync.

---

# 9. NOTA SALES — SATU SESI PEMBERANGKATAN

Buat workspace utama:

```text
Nota Sales
```

Tab:

1. Ringkasan;
2. Barang Dibawa;
3. Penjualan;
4. Nota/Piutang;
5. Penerimaan;
6. Biaya;
7. Pembelian/Kulakan;
8. Kas & Setoran;
9. Lampiran;
10. Rekonsiliasi;
11. Laporan/Audit.

## 9.1 Mulai sesi

Sales hanya dapat memulai SPJ berstatus APPROVED/DISPATCHED yang ditugaskan kepadanya. Server menolak dua sesi aktif untuk sales yang sama kecuali owner memiliki privilege exception.

## 9.2 Penerimaan piutang

Mendukung:

- lunas;
- bayar sebagian;
- gagal bayar;
- janji bayar;
- transfer langsung;
- tunai;
- QR/e-wallet;
- giro/BG bila existing;
- satu pembayaran untuk banyak invoice;
- satu invoice dibayar beberapa kali;
- kwitansi;
- attachment;
- reversal.

Overpayment ditolak secara default kecuali sistem existing mempunyai customer deposit yang disetujui.

## 9.3 Biaya

Sales dapat input:

- kategori;
- tanggal;
- nilai;
- metode;
- uraian;
- merchant/penerima;
- bukti;
- GPS opsional;
- sumber kas;
- status approval.

Biaya di atas threshold memerlukan approval owner. Edit setelah sinkron harus menjadi reversal+koreksi, bukan overwrite tanpa jejak.

## 9.4 Pembelian selama perjalanan

Reuse Kulakan:

- pilih supplier;
- nomor faktur;
- tanggal;
- produk;
- qty;
- harga;
- diskon;
- batch;
- expiry;
- pajak;
- pembayaran: cash, DP, credit;
- nilai dibayar;
- sisa hutang;
- due date;
- tujuan: stok mobil sales atau gudang;
- attachment;
- trip ID.

Jika tujuan stok mobil sales, barang masuk ke lokasi mobile stock dan tersedia untuk penjualan setelah posting server yang sah.

## 9.5 Kembali dan rekonsiliasi

Saat kembali:

- scan/hitung barang tersisa;
- hitung terjual;
- hitung rusak/hilang;
- rekonsiliasi invoice;
- rekonsiliasi collection;
- rekonsiliasi biaya;
- rekonsiliasi purchase;
- rekonsiliasi kas;
- catat setoran;
- tampilkan exception;
- sales submit;
- owner approve/close.

Final close online dan atomic.

---

# 10. RUMUS LAPORAN SESI

Rumus yang diminta bisnis:

```text
Hasil Bersih Sesi =
    Piutang Berhasil Dibayar
  - Biaya Transport/Tol/Parkir/Lain-lain
  - Pembayaran Aktual Pembelian Sales
```

Implementasi wajib membedakan:

- total invoice purchase;
- cash/transfer/DP yang dibayar;
- sisa hutang purchase;
- collection cash;
- collection transfer langsung;
- cash sale;
- uang muka;
- setoran owner;
- kas fisik.

Tampilkan dua blok:

### Hasil Operasional

```text
Penerimaan Piutang
(-) Biaya Sesi
(-) Pembayaran/DP Pembelian
(=) Hasil Bersih Sesi
```

### Rekonsiliasi Kas

```text
Uang Muka
+ Collection Tunai
+ Penjualan Tunai
- Biaya Tunai
- Pembelian Tunai/DP
- Setoran
= Kas Seharusnya
vs Kas Aktual
= Selisih
```

Jangan memasukkan barang yang masih berupa piutang sebagai penerimaan kas.

---

# 11. API JAVA YANG WAJIB

Gunakan prefix action `si_` untuk fitur baru agar tidak bentrok.

## Master

```text
si_supplier_list/detail/create/update/deactivate
si_customer_list/detail/create/update/deactivate
si_sales_list/detail/create/update/deactivate
si_product_detail
si_inventory_balance
si_inventory_ledger
```

## SPJ

```text
si_spj_generate_number
si_spj_list
si_spj_detail
si_spj_create
si_spj_update
si_spj_submit
si_spj_approve
si_spj_reject
si_spj_dispatch
si_spj_cancel
si_spj_print
si_spj_product_candidates
si_spj_products_bulk_add
si_spj_product_remove
si_spj_receivable_candidates
si_spj_receivables_bulk_add
si_spj_receivable_remove
```

## Sesi

```text
si_trip_start
si_trip_current
si_trip_detail
si_trip_return
si_trip_submit_reconciliation
si_trip_approve_reconciliation
si_trip_close
si_trip_reopen_exception
```

## Sales Order

```text
si_sales_order_list
si_sales_order_detail
si_sales_order_create
si_sales_order_update
si_sales_order_submit
si_sales_order_confirm
si_sales_order_ready
si_sales_order_deliver
si_sales_order_invoice
si_sales_order_cancel
si_sales_order_return
```

## Collection

```text
si_receivable_list
si_collection_create
si_collection_detail
si_collection_allocate
si_collection_reverse
si_collection_receipt
si_collection_history
```

## Expense

```text
si_expense_category_list
si_expense_list
si_expense_create
si_expense_update
si_expense_cancel
si_expense_approve
si_expense_reject
```

## Purchase

```text
si_trip_purchase_create
si_trip_purchase_link_existing
si_trip_purchase_detail
si_trip_purchase_payment
si_trip_purchase_reverse
```

Boleh mendelegasikan ke `kulakan_faktur_*` setelah kontrak dan transaction boundary diperbaiki.

## Reports

```text
si_trip_report
si_trip_report_pdf
si_trip_report_excel
si_receivable_aging_customer
si_receivable_aging_sales
si_payable_aging
si_stock_report
si_price_report
si_gross_profit_report
si_profit_loss_report
```

## Sync

```text
si_sync_pull
si_sync_push_batch
si_sync_command_status
si_sync_attachment_prepare
si_sync_attachment_commit
```

## 11.1 Envelope request

```json
{
  "action": "si_collection_create",
  "requestId": "uuid",
  "idempotencyKey": "uuid-stabil",
  "correlationId": "uuid-sesi",
  "deviceId": "device-id",
  "localEntityId": "uuid-lokal",
  "clientTime": "2026-08-11T12:30:00+07:00",
  "payloadVersion": 1,
  "data": {}
}
```

Selama transisi, dispatcher boleh menerima body datar existing, tetapi command baru harus dinormalisasi ke envelope internal.

## 11.2 Response

```json
{
  "status": "success",
  "requestId": "...",
  "serverTime": "...",
  "serverEntityId": 123,
  "serverReference": "NS/2026/08/0001",
  "version": 4,
  "syncStatus": "SYNCED",
  "data": {}
}
```

Error:

```json
{
  "status": "error",
  "code": "RECEIVABLE_ALREADY_ASSIGNED",
  "message": "Invoice telah dibawa sesi lain.",
  "retryable": false,
  "fieldErrors": {},
  "conflict": {}
}
```

## 11.3 Idempotency

- Buat idempotency key sekali di device;
- simpan ke SQLite sebelum HTTP;
- retry memakai key yang sama;
- server menyimpan hasil command;
- duplicate key mengembalikan hasil pertama;
- jangan membuat nomor dokumen kedua;
- attachment mempunyai key terpisah tetapi dependency pada command induk.

---

# 12. TRANSACTION BOUNDARY SERVER

Setiap operation posting memakai satu Hibernate transaction.

Contoh dispatch SPJ:

```text
lock SPJ
validate status/permission
reserve/generate number
create inventory transfer to mobile stock
mark invoice assignment
write status history
write audit
commit
```

Kegagalan salah satu langkah membatalkan seluruhnya.

Collection:

```text
lock invoice/subledger
validate balance
create receipt
allocate
update subledger/event
create cash/bank event
create journal event
update SPJ note result
write audit
commit
```

Purchase:

```text
create/validate invoice
receive inventory
record batch/expiry
create payable
record actual payment/DP
create cash/bank event
link trip
write accounting event/audit
commit
```

Gunakan session manual dengan `try/finally`; session yang dibuka manual wajib ditutup. Jangan menutup currentSession yang dikelola framework.

---

# 13. OFFLINE-FIRST FLUTTER

## 13.1 Core sync

Implementasikan `packages/core_sync` nyata. Minimal:

```text
SyncCommand
OutboxRepository
SyncCoordinator
SyncTransport
RetryPolicy
DependencyResolver
ConflictRepository
SyncStatusNotifier
```

## 13.2 Upgrade CoreDb

Tambahkan migration version berikutnya, tidak menghapus tabel existing.

Local table minimum:

```text
sales_cache
supplier_cache
customer_sales_cache
receivable_cache
payable_cache
spj_cache
spj_barang_cache
spj_nota_cache
trip_cache
sales_order_draft
sales_order_item_draft
collection_draft
collection_allocation_draft
expense_draft
purchase_trip_draft
attachment_outbox
sync_outbox
sync_conflict
sync_cursor
```

Kolom outbox:

- local ID;
- action;
- payload;
- idempotency key;
- correlation ID;
- dependency IDs;
- status;
- attempt count;
- next retry;
- last error;
- created;
- updated;
- server reference.

## 13.3 Kebijakan offline

Boleh offline:

- lihat cache;
- buat draft Sales Order;
- ubah draft sendiri;
- catat delivery provisional;
- catat collection provisional;
- catat expense;
- catat purchase;
- scan barang;
- upload attachment ke queue;
- return draft.

Online wajib secara default:

- approve SPJ;
- dispatch final bila stok server belum punya allocation block;
- invoice/post;
- reversal;
- close session final;
- journal posting;
- perubahan rekening/harga sensitif.

Bila bisnis menghendaki dispatch offline, implementasikan allocation block/server-issued stock authorization; jangan sekadar melewati validasi.

## 13.4 Konflik

- Master: optimistic version dan review;
- transaction posted: tidak merge field per field;
- duplicate command: idempotent replay;
- invoice already assigned: quarantine;
- balance changed: show before/after and require resolution;
- stock insufficient: quarantine/partial approval;
- closed period: reject with actionable message.

---

# 14. ARSITEKTUR FLUTTER

Buat feature modular, tetapi jangan refactor seluruh aplikasi sekaligus:

```text
lib/features/inventory_sales/
  domain/
  data/
  application/
  presentation/
    dashboard/
    masters/
    inventory/
    purchasing/
    sales_order/
    receivables/
    payables/
    sales_trip/
    reports/
```

Shared component:

```text
SearchablePartySelector
SearchableProductSelector
BulkSelectionSheet
MoneyField
QuantityField
DocumentStatusChip
SyncStatusChip
AuditTimeline
AttachmentPicker
ReportPreview
ResponsiveMasterDetail
```

Tambahkan menu ke `MenuEBisnis`/AppShell melalui product profile. Jangan membuat menu duplicate di drawer dan sidebar; satu registry.

## 14.1 Landing per role

- Admin existing: pertahankan landing existing kecuali user memilih variant workspace.
- Pemilik: Dashboard Inventory & Sales.
- Sales: “Sesi Hari Ini”; bila tidak ada SPJ, tampilkan tugas mendatang dan tombol refresh, bukan akses admin.
- Multi-role: role switcher existing; menu mengikuti active role.

---

# 15. INTEGRASI KULAKAN

Perluas `KulakanScreen` dengan backward compatibility.

Mode:

```text
Kulakan Toko
Kulakan dalam Sesi Sales
```

Field tambahan conditional:

- SPJ/session;
- payment type CASH/DP/CREDIT;
- paid amount;
- due date;
- destination stock;
- batch/expiry;
- tax;
- shipping;
- attachment;
- server/local sync status.

Jangan mengubah arti action existing bagi varian default. Payload baru bersifat optional dan server tetap menerima contract lama.

---

# 16. LAPORAN SESI SALES

## 16.1 Struktur

1. Identitas SPJ;
2. Identitas Sales;
3. Periode/jam;
4. Rute;
5. Barang dibawa;
6. Barang terjual;
7. Barang kembali;
8. Barang rusak/hilang;
9. Invoice dibawa;
10. Collection penuh/sebagian;
11. Invoice belum dibayar/janji bayar;
12. Penjualan baru;
13. Biaya;
14. Pembelian supplier;
15. Pembayaran/DP purchase;
16. Hutang purchase baru;
17. Hasil bersih;
18. Rekonsiliasi kas;
19. Selisih;
20. Exception;
21. Lampiran;
22. Approval/signature;
23. Audit dan checksum.

## 16.2 Output

- on-screen;
- PDF A4;
- Excel;
- share Android;
- print Windows;
- snapshot immutable;
- watermark Draft/Final/Reprint;
- audit download/print;
- QR validation.

---

# 17. MIGRATION DAN SEED

1. Buat migration additive.
2. Jangan hanya mengandalkan `hbm2ddl=update` di production.
3. Tambahkan mapping entity sesuai convention kedua `hibernate.cfg.xml` bila diperlukan.
4. Tambahkan tabel audit Envers.
5. Seed role/menu/kategori biaya secara idempotent.
6. Backfill tidak mengarang sales mapping.
7. Data existing tanpa sales masuk exception queue.
8. Nomor akun sales legacy yang tidak ada di COA tetap nullable/UAT_REQUIRED.
9. Migration dapat dijalankan ulang dengan aman.
10. Buat rollback data-level untuk fase pilot, bukan drop table.

---

# 18. KEAMANAN

- Bearer token tetap server-side validated;
- pertimbangkan migrasi token dari SharedPreferences ke secure storage secara kompatibel;
- rate limit login dan command sensitif;
- role/permission check per action;
- scope toko dan sales selalu dari server context;
- jangan menerima `salesId/tokoId` mentah tanpa verifikasi assignment;
- attachment antivirus/type/size validation;
- rekening/HPP/laba restricted;
- location optional dan consent-aware;
- audit immutable;
- re-auth/approval untuk reversal, close with variance, price below cost, account change;
- no secrets/log PII excessive.

---

# 19. PETA 48 LAYAR

Baca CSV:

```text
MAPPING_48_LAYAR_KE_ZISHOF_PLATFORM_DAN_JAVA_AIS.csv
```

Setiap layar berikut tetap requirement tersendiri, walaupun beberapa memakai route/komponen yang sama.


## Layar 01 — Data Supplier → Master Supplier

**Reuse existing:** Belum ada workspace supplier penuh; reuse selector supplier pada Kulakan dan audit PemasokProduk/Penyedia existing  
**Pekerjaan baru:** Buat Master Supplier + detail + status aktif/nonaktif  
**Aksi/API utama:** `si_supplier_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 01, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-01/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 02 — Membuka Daftar Supplier → Daftar Supplier

**Reuse existing:** Reuse pola tabel/paging AppShell dan picker supplier Kulakan  
**Pekerjaan baru:** Daftar search-first, filter, sort, pilih record tanpa menyimpan  
**Aksi/API utama:** `si_supplier_list`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 02, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-02/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 03 — Menutup Daftar Supplier → Detail Supplier

**Reuse existing:** Reuse responsive master-detail shell  
**Pekerjaan baru:** Tutup panel daftar tanpa mengubah record/draft  
**Aksi/API utama:** `client_ui_state`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 03, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-03/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 04 — Data Customer → Master Customer

**Reuse existing:** Reuse AnggotaScreen/AnggotaKoperasi setelah audit semantik  
**Pekerjaan baru:** Tambahkan profil customer sales: termin, diskon, limit, area, sales, saldo  
**Aksi/API utama:** `si_customer_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 04, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-04/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 05 — Membuka Daftar Customer → Daftar Customer

**Reuse existing:** Reuse pencarian anggota dan paging  
**Pekerjaan baru:** Search nama/kode/telepon/alamat; grid/card responsif  
**Aksi/API utama:** `si_customer_list`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 05, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-05/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 06 — Menutup Daftar Customer → Detail Customer

**Reuse existing:** Reuse responsive master-detail shell  
**Pekerjaan baru:** Pertahankan record terpilih dan unsaved-change guard  
**Aksi/API utama:** `client_ui_state`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 06, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-06/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 07 — Data Sales atau Penjual Keliling → Master Sales

**Reuse existing:** Baru; relasikan ke Tbmuser, Toko, Tbmrole  
**Pekerjaan baru:** CRUD Sales, area, target, akun, status, user login  
**Aksi/API utama:** `si_sales_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat profil sendiri; perubahan oleh Pemilik/Admin.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 07, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-07/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 08 — Data Stok Barang → Persediaan & Kartu Stok

**Reuse existing:** Reuse ProdukScreen, stok_dashboard, mutasi stok  
**Pekerjaan baru:** Saldo per lokasi termasuk Stok Mobil Sales; batch/expiry/HPP  
**Aksi/API utama:** `si_inventory_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 08, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-08/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 09 — Laporan Opname → Stok Opname

**Reuse existing:** Reuse StokOpnameScreen dan so_* API  
**Pekerjaan baru:** Tambah filter sales mobile stock dan session linkage  
**Aksi/API utama:** `so_* / si_stock_count_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 09, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-09/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 10 — Mencetak Laporan Opname → Cetak Opname

**Reuse existing:** Reuse PDF/printing  
**Pekerjaan baru:** PDF, Excel, berita acara, tanda tangan, audit reprint  
**Aksi/API utama:** `si_stock_count_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 10, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-10/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 11 — Harga Beli dan Harga Jual → Analisis Harga

**Reuse existing:** Reuse Produk/Diskon; audit harga existing  
**Pekerjaan baru:** Harga beli supplier dan harga jual customer effective-dated  
**Aksi/API utama:** `si_price_analysis`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 11, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-11/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 12 — Memilih dan Menjalankan Cetak Harga Beli/Jual → Parameter Laporan Harga

**Reuse existing:** Reuse LaporanScreen  
**Pekerjaan baru:** Filter pihak/produk/periode/status; preview sebelum cetak  
**Aksi/API utama:** `si_price_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 12, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-12/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 13 — Mencetak Harga Jual → Daftar Harga Jual

**Reuse existing:** Reuse PriceTag/PDF/printing  
**Pekerjaan baru:** Price list customer/umum, versi snapshot, reprint reason  
**Aksi/API utama:** `si_selling_price_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 13, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-13/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 14 — Mengekspor Data Harga/Stok ke Excel → Ekspor Harga & Stok

**Reuse existing:** Reuse produk_grid_ekspor_excel dan file handling  
**Pekerjaan baru:** Excel dengan filter, metadata, jumlah baris, audit  
**Aksi/API utama:** `si_inventory_export`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 14, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-14/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 15 — Mencetak Daftar Stok → Laporan Persediaan

**Reuse existing:** Reuse laporan katalog  
**Pekerjaan baru:** Stok per lokasi/batch/sales/warehouse dan nilai HPP  
**Aksi/API utama:** `si_stock_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 15, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-15/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 16 — Hasil Cetak Stok → Preview Laporan Persediaan

**Reuse existing:** Reuse PDF viewer/share  
**Pekerjaan baru:** Preview identik dengan cetak, total dan cut-off  
**Aksi/API utama:** `si_stock_report_preview`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 16, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-16/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 17 — Menu Master Harga → Master Harga

**Reuse existing:** Reuse Produk/Diskon sebagai dasar  
**Pekerjaan baru:** Workspace harga dengan versioning, approval, audit  
**Aksi/API utama:** `si_price_book_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 17, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-17/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 18 — Master Harga Beli per Supplier → Harga Beli Supplier

**Reuse existing:** Reuse Kulakan history  
**Pekerjaan baru:** Effective date, supplier-product, tier qty, approval  
**Aksi/API utama:** `si_supplier_price_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 18, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-18/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 19 — Master Harga Jual per Customer → Harga Jual Customer

**Reuse existing:** Reuse customer + produk  
**Pekerjaan baru:** Customer-product price, discount, margin guard, history  
**Aksi/API utama:** `si_customer_price_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 19, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-19/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 20 — Proses Pembelian Barang dari Supplier → Kulakan / Pembelian Supplier

**Reuse existing:** Perluas KulakanScreen dan kulakan_faktur_*  
**Pekerjaan baru:** Batch/expiry, pajak, termin, DP/kredit, tujuan stok, trip link  
**Aksi/API utama:** `si_purchase_* / kulakan_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 20, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-20/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 21 — Tombol Hutang pada Pembelian → Deep-link Hutang

**Reuse existing:** Reuse hasil Kulakan  
**Pekerjaan baru:** Buka subledger AP dari faktur tanpa membuat hutang ganda  
**Aksi/API utama:** `si_payable_from_purchase`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 21, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-21/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 22 — Data Hutang Supplier → Ledger Hutang

**Reuse existing:** Baru di Flutter; audit model payable existing  
**Pekerjaan baru:** Invoice, pembayaran, saldo, jatuh tempo, aging  
**Aksi/API utama:** `si_payable_list`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 22, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-22/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 23 — Menampilkan Hutang yang Sudah Lunas → Filter Hutang Lunas

**Reuse existing:** Reuse filter/status  
**Pekerjaan baru:** Tampilkan/sembunyikan settled tanpa delete  
**Aksi/API utama:** `si_payable_list`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 23, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-23/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 24 — Pembayaran Hutang → Pembayaran Supplier

**Reuse existing:** Reuse CaraPembayaran dan cash/bank context  
**Pekerjaan baru:** Cash/transfer/DP/alokasi multi-invoice, idempotent  
**Aksi/API utama:** `si_payable_payment_create`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 24, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-24/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 25 — Melihat Pembayaran Hutang → Riwayat Pembayaran Hutang

**Reuse existing:** Reuse history/detail dialog  
**Pekerjaan baru:** Detail alokasi, bukti, reversal, audit  
**Aksi/API utama:** `si_payable_payment_history`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 25, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-25/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 26 — Mencetak Pembayaran Hutang → Voucher Pembayaran Hutang

**Reuse existing:** Reuse PDF/printing  
**Pekerjaan baru:** Voucher, attachment, reprint audit  
**Aksi/API utama:** `si_payable_payment_receipt`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 26, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-26/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 27 — Analisis Hutang → Aging Hutang

**Reuse existing:** Reuse dashboard/chart components  
**Pekerjaan baru:** Aging supplier, due alerts, drill-down  
**Aksi/API utama:** `si_payable_aging`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 27, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-27/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 28 — Mencetak Faktur Pembelian Barang → Cetak Faktur Pembelian

**Reuse existing:** Reuse Kulakan detail  
**Pekerjaan baru:** Invoice purchase PDF/A4/thermal, snapshot  
**Aksi/API utama:** `si_purchase_invoice_print`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 28, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-28/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 29 — Mencetak Laporan Pembelian per Periode → Laporan Pembelian

**Reuse existing:** Reuse LaporanScreen  
**Pekerjaan baru:** Periode, supplier, sales trip, warehouse, cash/DP/credit  
**Aksi/API utama:** `si_purchase_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 29, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-29/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 30 — Menu Penjualan → Penjualan Sales / Sales Order

**Reuse existing:** Reuse product picker, Keranjang, Pesanan; jangan samakan order dengan invoice  
**Pekerjaan baru:** Mode Sales Lapangan: PESAN, SIAP_KIRIM, TERKIRIM, SIAP_TAGIH  
**Aksi/API utama:** `si_sales_order_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 30, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-30/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 31 — Membuka Piutang dari Menu Penjualan → Deep-link Piutang

**Reuse existing:** Reuse customer/order context  
**Pekerjaan baru:** Buka AR subledger yang sama tanpa duplikasi  
**Aksi/API utama:** `si_receivable_from_sale`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 31, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-31/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 32 — Data Piutang Customer → Ledger Piutang

**Reuse existing:** Baru; link transaksi existing  
**Pekerjaan baru:** Saldo, jatuh tempo, sales, invoice, alokasi  
**Aksi/API utama:** `si_receivable_list`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 32, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-32/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 33 — Menampilkan Piutang yang Sudah Lunas → Filter Piutang Lunas

**Reuse existing:** Reuse status filter  
**Pekerjaan baru:** Tampilkan/sembunyikan settled tanpa delete  
**Aksi/API utama:** `si_receivable_list`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 33, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-33/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 34 — Pembayaran Piutang → Penerimaan Piutang

**Reuse existing:** Reuse CaraPembayaran; baru allocation engine  
**Pekerjaan baru:** Full/partial, multi-invoice, cash/transfer, receipt  
**Aksi/API utama:** `si_collection_create`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 34, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-34/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 35 — Melihat Pembayaran Piutang → Riwayat Penerimaan

**Reuse existing:** Reuse detail/history  
**Pekerjaan baru:** Alokasi, attachment, user/device/location, reversal  
**Aksi/API utama:** `si_collection_history`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 35, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-35/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 36 — Mencetak Pembayaran Piutang → Kwitansi Penerimaan

**Reuse existing:** Reuse PDF/printing/share  
**Pekerjaan baru:** Kwitansi dan reprint reason  
**Aksi/API utama:** `si_collection_receipt`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 36, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-36/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 37 — Analisis Piutang per Customer → Aging Customer

**Reuse existing:** Reuse analytics components  
**Pekerjaan baru:** Aging, credit utilization, payment behavior  
**Aksi/API utama:** `si_receivable_aging_customer`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 37, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-37/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 38 — Analisis Piutang per Sales → Aging per Sales

**Reuse existing:** Reuse sales dashboard  
**Pekerjaan baru:** Assigned vs collected vs outstanding per sales/session  
**Aksi/API utama:** `si_receivable_aging_sales`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Terbatas pada data/sesi sendiri.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 38, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-38/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 39 — Sales Membawa Nota → Surat Perintah Sales Jalan

**Reuse existing:** Baru; pusat assignment barang dan invoice  
**Pekerjaan baru:** Auto number, pilih sales, departure, bulk notes, approval, print  
**Aksi/API utama:** `si_spj_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Operasional untuk SPJ/sesi yang ditugaskan.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 39, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-39/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 40 — Nota Sales → Sesi Nota Sales

**Reuse existing:** Baru; pusat aktivitas sales lapangan  
**Pekerjaan baru:** Barang, penjualan, collection, biaya, kulakan, return, settlement  
**Aksi/API utama:** `si_trip_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Operasional untuk SPJ/sesi yang ditugaskan.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 40, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-40/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 41 — Laporan Piutang → Laporan Sesi & Piutang

**Reuse existing:** Reuse LaporanScreen; tambah trip report  
**Pekerjaan baru:** Daftar invoice, collection, expense, purchase, cash reconciliation  
**Aksi/API utama:** `si_trip_report / si_receivable_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Operasional untuk SPJ/sesi yang ditugaskan.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 41, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-41/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 42 — Mencetak Laporan Piutang → Cetak Laporan Sesi/Piutang

**Reuse existing:** Reuse PDF/printing/share  
**Pekerjaan baru:** PDF/Excel, signature owner/sales, QR verification  
**Aksi/API utama:** `si_trip_report_pdf`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Operasional untuk SPJ/sesi yang ditugaskan.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 42, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-42/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 43 — Kas dan Jurnal → Kas/Bank/Jurnal

**Reuse existing:** Reuse CaraPembayaran, sesi kas, laporan keuangan  
**Pekerjaan baru:** Cash ledger session, journal events, owner settlement  
**Aksi/API utama:** `si_cash_journal_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 43, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-43/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 44 — Membuat Perkiraan Baru → Master Akun

**Reuse existing:** Audit akun existing; jangan duplikasi COA  
**Pekerjaan baru:** Create/update/deactivate account with RBAC  
**Aksi/API utama:** `si_coa_*`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 44, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-44/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 45 — Menu Laba/Rugi → Parameter Laba/Rugi

**Reuse existing:** Reuse laporan_keuangan_katalog  
**Pekerjaan baru:** Periode, toko, sales session, basis posting  
**Aksi/API utama:** `si_profit_loss_params`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 45, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-45/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 46 — Mencetak Laba Rugi Kotor → Laba Kotor

**Reuse existing:** Reuse transaction HPP snapshots  
**Pekerjaan baru:** Gross profit by product/customer/sales/session  
**Aksi/API utama:** `si_gross_profit_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 46, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-46/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 47 — Laporan Laba/Rugi → Laporan Laba/Rugi

**Reuse existing:** Reuse LaporanScreen  
**Pekerjaan baru:** Revenue, COGS, expense, net; drill-down journal  
**Aksi/API utama:** `si_profit_loss_report`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 47, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-47/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


## Layar 48 — Mencetak Laporan Laba/Rugi → Cetak Laba/Rugi

**Reuse existing:** Reuse PDF/Excel/printing  
**Pekerjaan baru:** Snapshot, watermark, version, reprint audit  
**Aksi/API utama:** `si_profit_loss_print`

### Kontrak UI

- Tampilkan konteks toko, role aktif, user, status koneksi, status sinkronisasi, tanggal/periode, dan nomor dokumen bila relevan.
- Seluruh tombol legacy pada Panduan 48 Layar harus memiliki handler nyata atau disabled reason berdasarkan status/permission.
- Desktop menggunakan tabel/master-detail bila sesuai; Android menggunakan kartu, wizard, drill-down, atau preview PDF tanpa menghilangkan field, kolom, total, filter, maupun aksi.
- Pencarian harus server-side/paged dan mempunyai cache offline; jangan memuat semua data tanpa batas.
- Unsaved-change guard, loading, empty state, retry, error code, dan audit link wajib.

### Server Java

- Audit entity/action existing sebelum membuat baru.
- Gunakan transaction atomic untuk perubahan saldo/stok/keuangan.
- Periksa role aktif, scope toko, assignment sales, status periode, optimistic version, dan idempotency key.
- Simpan snapshot historis untuk pihak, produk, harga, HPP, batch, expiry, sales, dan termin bila layar berhubungan dengan transaksi.
- Posted data dikoreksi dengan reversal/cancel, bukan delete.

### Offline

- Cache data baca.
- Persist draft/command sebelum network.
- Retry memakai idempotency key yang sama.
- Tampilkan PENDING, SYNCING, SYNCED, FAILED, CONFLICT, atau QUARANTINED.
- Restart aplikasi tidak boleh menghilangkan pekerjaan.
- Final posting/closing mengikuti matriks risiko.

### Hak akses

- Admin: penuh.
- Pemilik Sales/Inventory: penuh dalam scope toko/tenant.
- Sales Keliling: Lihat terbatas bila diperlukan; tidak boleh mengubah master/global.
- Server menguji hak; Flutter bukan sumber kebenaran.

### Test dan evidence

1. Java permission + transaction + validation test.
2. API integration test dengan PostgreSQL target.
3. Flutter unit/state test.
4. Widget test Windows lebar.
5. Widget/golden Android.
6. Offline/restart/retry/duplicate test.
7. Print/PDF/Excel bila relevan.
8. UAT membandingkan layar legacy 48, hasil data, total, dan status.
9. Evidence disimpan di `docs/pos-inventory-sales/evidence/screen-48/`.
10. Jangan tandai DONE bila satu surface/evidence wajib belum ada.


---

# 20. FASE IMPLEMENTASI

## P0 — Audit dan baseline

- lindungi working tree;
- buat feature branch;
- hash input;
- audit dua repo;
- jalankan build/test baseline;
- dokumentasikan failure existing;
- buat architecture decision log;
- buat requirement ledger 48 layar.

Output:

```text
docs/pos-inventory-sales/00-baseline.md
docs/pos-inventory-sales/01-gap-ledger.csv
docs/pos-inventory-sales/02-decisions.md
```

## P1 — Varian, bootstrap, shell, role

- product profile;
- Windows variant;
- Android flavor;
- icons/app IDs/installers;
- actor context resolver;
- role/menu seed;
- Sesi Flutter;
- menu registry;
- build CI matrix.

Definition of Done: varian dapat login sebagai tiga role dan menampilkan landing/menu yang tepat tanpa merusak varian existing.

## P2 — Foundation master dan inventory

Layar 01–19:

- supplier;
- customer;
- sales;
- product/stock;
- opname;
- reports;
- price books.

## P3 — Kulakan, AP, purchase reports

Layar 20–29:

- Kulakan extended;
- cash/DP/credit;
- payable;
- payment;
- aging;
- print/report;
- trip link.

## P4 — Sales Order, AR, collection

Layar 30–38:

- sales order lifecycle;
- delivery/invoice;
- receivable;
- collection;
- aging;
- receipt.

## P5 — SPJ dan Nota Sales

Layar 39–42 plus kebutuhan terbaru:

- SPJ;
- bulk products;
- bulk invoices;
- session;
- expenses;
- purchase;
- cash;
- return/reconcile;
- reports.

## P6 — Finance

Layar 43–48:

- cash/journal;
- COA;
- gross profit;
- profit/loss;
- print/export.

## P7 — Offline dan hardware

- typed outbox;
- restart;
- conflict;
- scanner;
- printer;
- attachment;
- Windows/Android device UAT.

## P8 — Migrasi, UAT, release

- DB migration rehearsal;
- legacy reconciliation;
- parallel run;
- 48-screen UAT;
- signing;
- installer/APK/AAB;
- checksums;
- release notes;
- rollback;
- hypercare.

---

# 21. TEST MATRIX WAJIB

## Java

- compile Java 1.7;
- unit test status machine;
- permission per role;
- active-role switch;
- scope toko;
- sales assignment;
- numbering concurrency;
- idempotency;
- optimistic lock;
- partial collection;
- overpayment;
- purchase cash/DP/credit;
- stock movement;
- return/damage/loss;
- close with variance;
- reversal;
- report totals;
- Envers audit;
- session close in finally.

## Flutter

- `flutter analyze`;
- all current tests;
- new domain tests;
- responsive tests 390px, tablet, 1366px, 1600px;
- golden per critical screen;
- keyboard desktop;
- camera scanner Android;
- USB scanner text input Windows;
- offline from start;
- offline after data loaded;
- process kill/restart;
- retry same command;
- duplicate response;
- conflict;
- attachment queue;
- permission visibility and server rejection;
- PDF/share/print.

## UAT session

Scenario minimum:

1. Owner creates SPJ with products and 10 invoices.
2. Owner approves and prints.
3. Sales starts offline.
4. Sales creates an order.
5. Sales delivers another order.
6. Sales receives full payment.
7. Sales receives partial payment.
8. Customer promises payment.
9. Sales records fuel, toll, parking.
10. Sales purchases supplier goods cash.
11. Sales purchases with DP.
12. Goods enter mobile stock.
13. Network returns and sync occurs.
14. Duplicate retry does not duplicate.
15. Sales returns goods and cash.
16. Owner reconciles.
17. Formula matches.
18. Owner closes and prints final report.
19. Reprint has watermark/audit.
20. Ledger stock/AP/AR/cash/journal reconcile.

---

# 22. DEFINITION OF DONE

Satu requirement hanya `DONE` bila:

- migration additive tersedia;
- entity/relationship valid;
- API server implemented;
- permission server implemented;
- audit implemented;
- Flutter Windows implemented;
- Flutter Android implemented;
- offline behavior implemented;
- print/export implemented bila relevan;
- automated tests pass;
- UAT pass;
- evidence path valid;
- no placeholder/hardcoded response;
- docs and changelog updated;
- commit hash recorded.

Status tracker:

```text
NOT_STARTED
AUDITED
DESIGNED
BACKEND_DONE
WINDOWS_DONE
ANDROID_DONE
OFFLINE_DONE
TESTED
UAT_PASSED
DONE
BLOCKED
```

---

# 23. GIT DAN COMMIT

Sebelum coding:

```powershell
cd C:\opt\CodeBaseDesktopDanMobile
git status --short
git branch --show-current
git remote -v
git rev-parse HEAD

cd C:\opt\AIS\ais\src\main
git status --short
git branch --show-current
git remote -v
git rev-parse HEAD
```

Buat branch terpisah di masing-masing repo, contoh:

```text
feat/flutter-pos-inventory-sales-48-screen
feat/java-api-pos-inventory-sales-trip
```

Jangan mencampur generated build/APK besar ke source tanpa kebijakan release. Commit per vertical slice, bukan satu commit raksasa.

---

# 24. ARTEFAK WAJIB DARI CODEX/CLAUDE

```text
docs/pos-inventory-sales/
  00-baseline.md
  01-source-inventory.md
  02-gap-ledger.csv
  03-architecture.md
  04-erd.md
  05-api-contract.md
  06-rbac-matrix.csv
  07-offline-contract.md
  08-48-screen-mapping.csv
  09-test-matrix.csv
  10-migration-plan.md
  11-uat-plan.md
  12-release-plan.md
  evidence/
  handover.md
```

Sertakan:

- file berubah;
- migration;
- commands run;
- output test;
- screenshot/golden;
- APK/installer checksum;
- known limitations;
- UAT_REQUIRED;
- commit SHA tiap repo.

---

# 25. PERINTAH EKSEKUSI AKHIR

Mulai dari P0. Jangan hanya menulis rencana.

1. Audit kedua repository dan bahan 48 layar.
2. Catat baseline.
3. Implementasikan extension hook `ApiEBisnis` secara kompatibel.
4. Implementasikan actor context/RBAC secara fail-closed.
5. Buat varian build `inventory_sales`.
6. Bangun vertical slice dari role → SPJ → barang/nota → session → order/collection/expense/purchase → reconciliation/report.
7. Implementasikan 48 layar sesuai mapping.
8. Jalankan build/test setiap fase.
9. Simpan evidence.
10. Commit masing-masing repo.
11. Jangan menandai pekerjaan selesai sebelum seluruh Definition of Done terpenuhi.

Saat melaporkan hasil, gunakan format:

```text
FASE:
STATUS:
FILES CHANGED:
MIGRATIONS:
API ACTIONS:
WINDOWS:
ANDROID:
OFFLINE:
TESTS RUN:
RESULT:
EVIDENCE:
COMMIT:
BLOCKERS/UAT_REQUIRED:
NEXT:
```
