# Analisis implementasi modul Pergudangan

Tanggal analisis: 25 Agustus 2026  
Status: **analisis dan rancangan awal; belum diimplementasikan**  
Sumber utama: `C:\Users\Admin1\Downloads\Inventory.pdf` (72 halaman)  
Repository server: `C:\opt\AIS\ais`  
Repository Desktop/Android: `C:\opt\CodeBaseDesktopDanMobile`

## 1. Tujuan dan batas tahap ini

Dokumen ini menjadi dasar keputusan sebelum menu **Pergudangan** dibuat. Analisis
mencakup kebutuhan pada dokumen sumber, kemampuan yang sudah tersedia, kesenjangan,
rancangan proses dan data, integrasi akuntansi, hak akses, performa, migrasi, serta
UAT.

Pada tahap ini **belum dilakukan**:

- penambahan menu, tabel, API, atau layar;
- perubahan perhitungan stok;
- migrasi database;
- build, deploy, commit, atau publikasi release.

Dokumen sumber adalah panduan proses inventory berbasis OpenERP/Odoo lama, bukan
spesifikasi ECAMPUS/eBisnis yang siap disalin. Konsep bisnisnya relevan, tetapi nama
menu, model data, jurnal, keamanan, dan UX harus disesuaikan dengan arsitektur yang
sekarang.

## 2. Kesimpulan eksekutif

Menu Pergudangan sebaiknya dibangun sebagai **lapisan WMS (warehouse management)**
di atas sumber kebenaran stok yang telah ada. Jangan membuat ledger stok kedua.

Keputusan arsitektur yang direkomendasikan:

1. Satu produk dan satu transaksi bisnis tetap menggunakan model inventory yang
   sekarang; dimensi `gudang`, `lokasi`, `batch/lot`, dan `status` ditambahkan pada
   pergerakan yang memerlukannya.
2. Saldo per lokasi adalah proyeksi/materialisasi dari pergerakan yang tervalidasi,
   bukan angka bebas yang diedit langsung.
3. Transfer antargudang memakai dua tahap: `KIRIM -> TRANSIT -> TERIMA`, mendukung
   penerimaan sebagian, selisih, rusak, dan backorder.
4. Lokasi fisik dipisahkan dari lokasi virtual (transit, rusak, hilang, retur,
   produksi, pelanggan, supplier). Pemindahan ke lokasi virtual tetap terlacak dan
   tidak boleh sekadar mengurangi angka stok tanpa dokumen.
5. Semua mutasi bernilai finansial menghasilkan referensi jurnal yang idempoten.
   Perubahan/void dilakukan dengan reversal, bukan menghapus histori.
6. Fitur dirilis bertahap. Fase pertama harus menutup alur penerimaan, putaway,
   transfer, opname, dan kartu stok sebelum otomasi reorder atau fitur lanjut.
7. UI Desktop dan Android memakai kontrak API yang sama. JSP/ZK tetap memperoleh
   layar operasional/administrasi yang setara sesuai kebutuhan, bukan implementasi
   logika bisnis terpisah.

## 3. Pemetaan kebutuhan dari dokumen sumber

| Area | Halaman sumber | Kebutuhan yang ditarik untuk eBisnis |
|---|---:|---|
| Konfigurasi persediaan | 1-3, 20-21 | perpetual inventory, metode biaya, multi-gudang/lokasi, lot/serial/kedaluwarsa |
| Reservasi dan fulfillment | 4-7 | reservasi stok, picking, pengiriman bertahap, pembatasan lokasi per pengguna |
| Lokasi virtual | 8, 32-36 | transit, inventory loss, rusak, sample, retur, supplier, pelanggan |
| Kategori produk | 9 | kategori sebagai pengendali akun, aturan stok, dan analitik |
| Satuan ukuran | 10-12 | UOM dasar/beli/jual dan konversi yang konsisten |
| Saldo awal dan traceability | 13-19 | saldo awal, on-hand, forecast, incoming/outgoing, riwayat pergerakan |
| Transfer antargudang | 22-31 | sumber-transit-tujuan, konfirmasi penerimaan, parsial/backorder |
| Stock opname | 37-44 | sesi hitung, snapshot sistem, fisik, selisih, approval, jurnal penyesuaian |
| Reorder point | 45-52 | minimum/maksimum, lead time, supplier, draft PO, scheduler |
| Retur | 53-57 | lokasi retur, penerimaan retur, dampak stok dan nilai |
| Lot/serial/expiry | 58-68 | lot/serial saat terima/kirim, expired/best-before/removal/EOL |
| Laporan | 69-72 | inventory at date dan valuation per tanggal/lokasi/kategori |

Hal yang tidak boleh diadopsi mentah dari dokumen:

- label dan navigasi OpenERP;
- anggapan satu company/satu chart of accounts;
- penyimpanan saldo sebagai hasil edit langsung;
- pemrosesan sinkron untuk pekerjaan massal;
- asumsi semua pengguna boleh melihat seluruh lokasi.

## 4. Kondisi repository saat ini

### 4.1 Fondasi server yang dapat dipakai ulang

| Kemampuan | Model/file saat ini | Penilaian |
|---|---|---|
| Gudang hierarkis | `ais.database.model.sirs.Gudang` / `sirs.gudang` | Ada kode, nama, alamat, gudang induk, aktif. Perlu audit batas domain karena berada di schema `sirs`. |
| Lokasi | `ais.database.model.asset.Lokasi` / `asset.lokasi` | Sudah terhubung ke gudang, toko, bagian, dan jenis lokasi. Kandidat kuat untuk lokasi fisik/virtual setelah aturan tipenya dipertegas. |
| Transfer dua tahap | `asset.PengirimanGudang` | Sudah memiliki lokasi asal, tujuan, transit, tanggal kirim/terima, status, petugas, dan catatan. |
| Detail transfer | `asset.PengirimanGudangDetail` | Sudah menyimpan produk, qty kirim/terima/rusak dan harga satuan. Mendekati kebutuhan parsial/selisih. |
| Mutasi antar toko | `inventory.MutasiStokToko` | Cocok sebagai kompatibilitas proses lama, tetapi belum cukup sebagai dokumen WMS lengkap. |
| Produk batch | `inventory.ProdukBatch` | Sudah memiliki produk, toko, nomor batch, tanggal produksi/kedaluwarsa, stok, harga modal, status. |
| Ledger batch | `inventory.MutasiProdukBatch` | Ada masuk, keluar, saldo, jenis, referensi, waktu, keterangan, pelaku. |
| Stock opname | `inventory.SesiStokOpname`, `inventory.StokOpname` | Ada sesi dan rincian sistem/fisik/selisih; perlu dimensi lokasi, snapshot, approval, dan locking. |
| Reorder minimum | `inventory.AmbangStokGudang` | Ada produk, gudang, ambang minimum, aktif, catatan; belum ada maksimum, lead time, UOM, supplier prioritas. |
| Pengadaan | `inventory.PengadaanFaktur`, `inventory.PengadaanProduk` | Sudah mencatat faktur, supplier, toko, qty, harga, waktu. Bisa menjadi sumber dokumen penerimaan. |
| Retur | `inventory.ReturPembelian`, `inventory.ReturPenjualan` | Sudah ada proses retur; perlu diarahkan ke lokasi retur dan status QC. |
| Konteks toko | `inventory.Toko` | Memiliki `gudangPemasok` dan akun-akun akuntansi; perlu kebijakan default gudang/lokasi. |

Server juga telah mempunyai layanan stok di `ais.action.servlet.api.KantinHelper`
untuk perhitungan stok, mutasi ledger, batch, kedaluwarsa, opname, kulakan, retur,
rekonsiliasi, dan dashboard. Layanan ini harus menjadi jalur integrasi, bukan
didobel di helper Pergudangan baru tanpa kontrak bersama.

### 4.2 Fondasi UI/menu yang dapat dipakai ulang

- katalog hak akses server berada di
  `ais.common.EbisnisMenuKatalog`;
- shell Desktop/Android berada di
  `apps/ebisnis/lib/widgets/app_shell.dart` dan `app_drawer.dart`;
- layar yang sudah ada: Produk, Stok Opname, Kedaluwarsa, Mutasi Antar Outlet,
  Kulakan, Retur Pembelian, dan paket Inventory & Sales;
- varian Inventory & Sales sudah memiliki `Persediaan & Kartu Stok`, master
  supplier/customer, harga, pembelian, penjualan, kas/jurnal, dan laporan.

### 4.3 Masalah arsitektur yang harus diselesaikan dahulu

1. **Gudang lintas domain.** `sirs.Gudang` dipakai oleh inventory, sedangkan lokasi
   berada di schema asset. Sebelum memperluas tabel, perlu diputuskan apakah gudang
   tersebut memang entitas enterprise bersama. Jika semantik medis melekat kuat,
   buat model inventory netral dan migrasikan referensi secara kompatibel.
2. **Dua jalur transfer.** `MutasiStokToko` dan `PengirimanGudang` tidak boleh menjadi
   dua sumber kebenaran. `PengirimanGudang` sebaiknya menjadi dokumen/header WMS;
   postingnya menghasilkan ledger inventory dan kompatibilitas mutasi toko.
3. **Tipe angka.** Kuantitas sekarang banyak memakai `Double`. Untuk fitur baru,
   gunakan tipe database `numeric` dan `BigDecimal` di Java agar konversi UOM dan
   valuasi tidak menghasilkan error pembulatan.
4. **Saldo tersimpan pada batch.** `ProdukBatch.stok` dan
   `MutasiProdukBatch.saldo` perlu diperlakukan sebagai cache/proyeksi yang dapat
   direkonsiliasi dari ledger, bukan kebenaran ganda.

## 5. Struktur menu Pergudangan yang direkomendasikan

Menu induk **Pergudangan** mempunyai landing dashboard dan submenu berikut:

1. **Dashboard Gudang**
   - stok on-hand, available, reserved, incoming, outgoing, transit;
   - penerimaan/pengiriman terlambat;
   - stok minimum, kedaluwarsa, selisih opname, nilai persediaan;
   - antrean tugas per peran dan gudang.
2. **Master Gudang & Lokasi**
   - gudang, zona, lorong, rak, bin;
   - lokasi fisik/virtual;
   - kapasitas, prioritas putaway/picking, status blokir;
   - pengguna/grup yang boleh mengakses.
3. **Penerimaan Barang**
   - dari PO/kulakan/retur/transfer/produksi;
   - pemeriksaan kuantitas, batch/serial, expiry, harga;
   - QC dan putaway.
4. **Putaway & Relokasi**
   - tugas pemindahan dock/QC ke lokasi simpan;
   - relokasi internal dengan scan asal dan tujuan.
5. **Transfer Antargudang**
   - permintaan, persetujuan, picking, kirim, transit, terima;
   - parsial, rusak, selisih, backorder, pembatalan/reversal.
6. **Picking, Packing & Pengeluaran**
   - reservasi order, wave/batch picking, packing, serah terima;
   - FEFO/FIFO dan validasi lot/serial.
7. **Stock Opname**
   - cycle count/full count, blind count, freeze/snapshot;
   - recount, approval selisih, posting penyesuaian.
8. **Batch, Serial & Kedaluwarsa**
   - traceability masuk/keluar, karantina, recall;
   - expired, best-before, removal, end-of-life.
9. **Replenishment & Reorder**
   - minimum/maksimum/safety stock/lead time;
   - usulan transfer atau draft PO, bukan posting otomatis tanpa review.
10. **Retur & Lokasi Virtual**
    - retur pembelian/penjualan, rusak, hilang, sample, karantina;
    - alasan, bukti, otorisasi, jurnal/reversal.
11. **Kartu Stok & Laporan**
    - saldo/nilai per tanggal, gudang, lokasi, batch, kategori;
    - aging, slow/fast moving, dead stock, akurasi opname;
    - ekspor Excel/PDF dengan audit filter.
12. **Konfigurasi Pergudangan**
    - kebijakan valuasi, default lokasi, FEFO/FIFO, toleransi, approval,
      penomoran, scheduler, dan integrasi akuntansi.

Untuk fase pertama, tampilkan hanya submenu 1-7, 10, dan 11 yang telah mempunyai
fondasi proses. Fitur serial, wave picking, kapasitas, dan replenishment otomatis
dapat diaktifkan setelah data dasar stabil.

## 6. Peran dan hak akses

Hak akses harus fail-closed dan terpisah antara melihat, membuat, mengonfirmasi,
membatalkan, serta memposting jurnal.

| Peran | Akses utama |
|---|---|
| Admin sistem | konfigurasi teknis dan seluruh menu, tetap tercatat dalam audit |
| Kepala gudang | dashboard, approval transfer/opname/selisih, konfigurasi operasional |
| Petugas penerimaan | terima, QC awal, catat lot/serial/expiry, cetak label |
| Petugas putaway | melihat dan menyelesaikan tugas putaway/relokasi |
| Picker/Packer | reservasi yang ditugaskan, picking, packing, handover |
| Petugas pengiriman | validasi muat/kirim dan dokumen serah terima |
| Petugas opname | input hitung; tidak boleh melihat stok sistem saat blind count |
| Supervisor | approve recount/selisih/void/reversal sesuai batas nilai |
| Akuntansi | valuasi, rekonsiliasi, posting jurnal; tidak mengubah qty fisik |
| Auditor | baca seluruh histori, perbandingan, dokumen, dan jurnal tanpa mutasi |

Kunci menu baru disarankan memakai prefix `gudang_`, misalnya
`gudang_dashboard`, `gudang_master`, `gudang_penerimaan`, `gudang_transfer`,
`gudang_opname`, dan `gudang_laporan`. Aksi sensitif memakai permission tersendiri,
misalnya `gudang_transfer_approve` dan `gudang_opname_post`.

## 7. Model data yang direkomendasikan

### 7.1 Prinsip

- pertahankan tabel lama dan lakukan migrasi evolusioner;
- dokumen transaksi adalah header/detail;
- setiap posting menghasilkan baris ledger append-only;
- setiap permintaan mutasi mempunyai `idempotency_key` unik per tenant/toko;
- saldo cepat berasal dari proyeksi yang dapat dibangun ulang;
- semua tabel operasional mempunyai tenant/toko, audit create/update, versi, status,
  serta referensi dokumen asal.

### 7.2 Entitas yang dipakai/ditingkatkan

- `sirs.gudang`: audit dahulu; tambahkan relasi tenant/toko dan kode unik scoped bila
  diputuskan menjadi master enterprise;
- `asset.lokasi`: pertahankan sebagai lokasi, tambahkan kode, path hierarki,
  `tipe_lokasi`, kapasitas, urutan picking/putaway, dan status blokir;
- `asset.pengiriman_gudang` + detail: gunakan sebagai awal dokumen transfer, lalu
  tambah status eksplisit, nomor versi, approval, backorder, dan idempotensi;
- `koperasi.produk_batch`: perlu nomor lot unik scoped, tanggal lengkap, status QC,
  serta relasi lokasi;
- `koperasi.sesi_stok_opname`/`stok_opname`: tambah lokasi, snapshot, blind count,
  putaran hitung, approver, dan referensi posting;
- `koperasi.ambang_stok_gudang`: tambah min, max, safety stock, lead time, UOM,
  supplier dan sumber replenishment.

### 7.3 Entitas/proyeksi baru yang diperlukan

Nama final mengikuti konvensi schema setelah audit. Rancangan logis:

1. `pergerakan_stok`
   - produk, gudang, lokasi asal/tujuan, batch/serial, qty dasar;
   - jenis, waktu efektif, dokumen/referensi, idempotency key;
   - harga/unit cost, nilai masuk/keluar, actor/device;
   - reversal dari baris mana dan status posting.
2. `saldo_stok_lokasi`
   - produk + lokasi + batch sebagai unique key;
   - on_hand, reserved, available, incoming, outgoing;
   - versi optimistic locking dan waktu proyeksi.
3. `reservasi_stok`
   - dokumen permintaan, produk/lokasi/batch, qty, expiry reservasi, status.
4. `tugas_gudang`
   - tipe receiving/QC/putaway/pick/pack/count, assignee, prioritas, SLA, status.
5. `serial_produk` bila serial tracking diaktifkan.
6. `kebijakan_gudang` dan `akses_lokasi_grup`.
7. `reorder_rule`/`replenishment_run` bila `AmbangStokGudang` tidak cukup.

Jangan membuat tabel harian dinamis. Gunakan tabel stabil, indeks yang benar, dan
partisi PostgreSQL bulanan bila volume ledger membesar. Tabel per tanggal akan
membuat query lintas tanggal, migrasi, hak akses, dan maintenance sangat rapuh.

### 7.4 Constraint dan indeks minimum

- unique `(tenant_id, kode)` untuk gudang/lokasi/dokumen;
- unique `(tenant_id, idempotency_key)` untuk posting;
- check qty positif pada detail; arah ditentukan asal/tujuan;
- check asal berbeda dari tujuan;
- check lot/serial wajib sesuai konfigurasi produk;
- indeks ledger `(tenant_id, produk_id, waktu_efektif, id)`;
- indeks `(lokasi_id, produk_id, batch_id)` dan status/waktu tugas;
- partial index untuk dokumen aktif/pending dan batch mendekati expiry;
- foreign key `RESTRICT` untuk master yang sudah pernah dipakai;
- optimistic version pada header/proyeksi saldo.

## 8. State machine utama

### 8.1 Penerimaan

`DRAFT -> DIJADWALKAN -> TIBA -> DIPERIKSA -> DITERIMA -> PUTAWAY -> SELESAI`

Cabang: `DITOLAK`, `KARANTINA`, `DITERIMA_SEBAGIAN`, `DIBATALKAN`. Posting stok
fisik terjadi pada titik yang dipilih kebijakan (setelah receipt atau setelah QC),
tetapi harus konsisten dan eksplisit.

### 8.2 Transfer antargudang

`DRAFT -> DIAJUKAN -> DISETUJUI -> DIPICK -> DIKIRIM -> TRANSIT -> DITERIMA`

Penerimaan parsial membuat detail backorder untuk sisa. Selisih/rusak masuk lokasi
virtual yang sesuai dan memerlukan alasan serta approval. Pembatalan setelah kirim
harus berupa return/reversal, bukan mengubah status kembali ke draft.

### 8.3 Stock opname

`DRAFT -> SNAPSHOT -> MENGHITUNG -> RECOUNT -> MENUNGGU_APPROVAL -> DIPOSTING`

Saat snapshot, transaksi dapat dibekukan per lokasi atau direkam sebagai movement
setelah snapshot agar rekonsiliasi deterministik. Selisih yang diposting membuat
movement adjustment dan jurnal; sesi yang sudah diposting tidak dapat diedit.

### 8.4 Picking/pengeluaran

`REQUESTED -> RESERVED -> PICKING -> PICKED -> PACKED -> SHIPPED -> DONE`

FEFO wajib untuk barang ber-expiry kecuali override supervisor dengan alasan.

## 9. Valuasi dan integrasi akuntansi

Konfigurasi harus menentukan metode yang benar-benar didukung: minimal Average dan
FIFO; Standard Cost hanya bila bisnis membutuhkannya. Jangan mencampur metode dalam
satu kategori tanpa tanggal efektif.

Peristiwa jurnal minimum:

- penerimaan supplier: persediaan vs barang diterima belum ditagih/hutang;
- pengeluaran penjualan: HPP vs persediaan;
- transfer internal satu entitas: tidak mengubah nilai total, hanya dimensi lokasi;
- transfer lintas unit hukum: memakai akun antar unit bila berlaku;
- opname lebih/kurang, rusak, hilang, sample: akun penyesuaian sesuai jenis;
- retur: reversal terhadap transaksi asal sejauh dapat ditelusuri.

Setiap ledger stok menyimpan `journal_reference`; jurnal menyimpan referensi movement.
Rekonsiliasi memeriksa qty, nilai inventory, dan jurnal pada periode yang sama.

## 10. Kontrak API dan implementasi server

API disarankan berbasis aksi yang konsisten dengan aplikasi saat ini, tetapi kontrak
payload/result harus versioned. Kelompok awal:

- `gudang_dashboard`, `gudang_list`, `gudang_lokasi_list/save`;
- `gudang_penerimaan_list/detail/save/confirm/putaway`;
- `gudang_transfer_list/detail/save/approve/ship/receive/cancel`;
- `gudang_tugas_list/assign/complete`;
- `gudang_opname_list/detail/start/count/approve/post`;
- `gudang_stok_list`, `gudang_kartu_stok`, `gudang_valuation`;
- `gudang_reorder_list/generate/review`.

Ketentuan teknis:

- kompatibel Java 1.7 dan gaya Java 1.6; tanpa lambda, Stream API,
  try-with-resources, atau diamond operator;
- uang dan qty baru memakai `BigDecimal`/`numeric`;
- transaksi database eksplisit; rollback pada error;
- `openSession()`/`currentNativeSession()` wajib `clear`, `disconnect`, `close` di
  `finally`; `currentSession()` tidak ditutup manual;
- query diparameterisasi dan dibatasi tenant/toko/lokasi;
- endpoint list selalu server-side pagination/filter/sort;
- pekerjaan massal (reorder, rebuild saldo, ekspor) berjalan sebagai job dengan
  progress, heartbeat, retry, dan hasil yang dapat diunduh;
- idempotency key diwajibkan pada confirm/ship/receive/post agar double-click atau
  retry offline tidak menggandakan mutasi;
- audit mencatat before/after, actor, perangkat, IP, waktu, dan alasan.

## 11. UX Desktop, Android, JSP, dan ZK

### Desktop

- layout master-detail responsif, sidebar collapsible;
- scanner-first, shortcut keyboard, tabel 10/25/50 per halaman;
- drawer detail tanpa kehilangan filter/scroll;
- status dan progress live untuk tugas/job;
- offline queue hanya untuk operasi yang aman dan idempoten.

### Android

- alur satu tugas per layar: scan lokasi -> scan barang -> qty -> konfirmasi;
- dukungan kamera/barcode scanner, feedback getar/suara;
- cache penugasan dan master minimum, bukan seluruh histori;
- indikator offline/sync/conflict yang informatif.

### JSP/ZK

- diprioritaskan untuk master, approval, audit, rekonsiliasi, dan laporan;
- memakai service/API bisnis yang sama, tidak menulis ledger sendiri;
- ZUL/JSP/CSS ditempatkan di folder webapp sesuai struktur eksisting;
- RBAC server tetap menjadi pengaman final meskipun tombol disembunyikan di UI.

Semua angka dashboard harus dapat ditelusuri ke daftar rinci dengan filter yang sama.
Ekspor harus menghormati filter, hak akses, zona waktu, dan snapshot tanggal.

## 12. Performa, skala, dan konsistensi

Target rancangan harus tetap responsif pada puluhan ribu produk dan ratusan ribu
movement/transaksi.

- jangan memuat seluruh produk, batch, lokasi, atau riwayat saat membuka menu;
- autocomplete mulai 2-3 karakter, debounce, limit, keyset pagination;
- dashboard membaca tabel agregat/materialized projection;
- kartu stok memakai `(waktu, id)` sebagai cursor;
- laporan nilai per tanggal memakai snapshot periodik + delta ledger;
- hindari N+1 Hibernate; ambil DTO/scalar yang dibutuhkan;
- stok tersedia diubah dengan atomic update/locking terukur;
- sediakan rekonsiliasi dan rebuild proyeksi tanpa menghentikan transaksi;
- partisi ledger bulanan baru dipakai berdasarkan pengukuran volume, bukan sejak awal;
- index dan query diverifikasi dengan `EXPLAIN (ANALYZE, BUFFERS)` pada data UAT.

## 13. Migrasi dan kompatibilitas

1. Inventarisasi semua formula stok lama pada `KantinHelper`, POS, pengadaan, retur,
   mutasi, produksi, dan apotik.
2. Tambah schema/kolom nullable serta master lokasi default per toko.
3. Backfill gudang/lokasi default untuk data lama tanpa mengubah total stok.
4. Bangun ledger/proyeksi dari histori dengan job resumable dan checksum.
5. Jalankan dual-read/reconciliation; jangan dual-write permanen.
6. Aktifkan write path baru per toko menggunakan feature flag.
7. Bandingkan saldo lama vs saldo per lokasi per produk/batch.
8. Setelah stabil, jadikan ledger baru sumber proyeksi; pertahankan adapter untuk
   laporan/API lama selama masa kompatibilitas.

Data lama tanpa lokasi tidak boleh hilang; masukkan ke lokasi default bertanda
`MIGRASI_AWAL` dengan referensi audit.

## 14. Tahapan implementasi

### Fase 0 - audit dan kontrak

- putuskan ownership `sirs.Gudang` dan `asset.Lokasi`;
- katalog seluruh sumber perubahan stok;
- definisikan formula on-hand/available/reserved/transit dan valuasi;
- finalisasi state machine, permission, dan kontrak API.

### Fase 1 - fondasi lokasi dan ledger

- master gudang/lokasi fisik/virtual;
- movement append-only, saldo proyeksi, rekonsiliasi;
- dashboard dasar dan kartu stok per lokasi.

### Fase 2 - receiving, putaway, transfer

- penerimaan dari pengadaan;
- QC/putaway;
- transfer transit, parsial, rusak, backorder.

### Fase 3 - opname dan retur

- cycle/full/blind count, recount, approval, adjustment;
- retur dan lokasi karantina/rusak.

### Fase 4 - lot/serial/expiry dan fulfillment

- FEFO/FIFO, serial tracking, recall;
- reservation, picking, packing, shipment.

### Fase 5 - replenishment dan analitik

- min/max/safety stock, lead time, draft PO/usulan transfer;
- inventory at date, valuation, aging, slow moving, akurasi gudang.

Setiap fase harus dapat diaktifkan per toko, dapat di-rollback tanpa menghapus data,
dan mempunyai migrasi serta UAT tersendiri.

## 15. UAT dan kriteria penerimaan

### 15.1 UAT fungsional minimum

1. Terima PO penuh dan parsial; qty, batch, lokasi, nilai, dan jurnal benar.
2. Transfer A -> transit -> B penuh/parsial; total enterprise tidak berubah.
3. Terima rusak/kurang/lebih; lokasi virtual dan approval benar.
4. Double-click/retry request tidak membuat movement ganda.
5. Putaway/relokasi mengubah lokasi tanpa mengubah total perusahaan.
6. Opname snapshot saat transaksi berjalan menghasilkan selisih deterministik.
7. Retur pembelian/penjualan menelusuri dokumen asal dan nilai yang tepat.
8. FEFO memilih batch benar; override memerlukan supervisor dan alasan.
9. Produk serial tidak dapat dikirim dua kali.
10. Inventory at date sama dengan penjumlahan ledger hingga timestamp tersebut.
11. Valuasi sama dengan jurnal persediaan pada cutoff.
12. Pengguna gudang A tidak melihat/mengubah gudang B tanpa hak.

### 15.2 UAT kompatibilitas

- POS, kulakan, retur, mutasi, opname, apotik, produksi, dan laporan lama tetap jalan;
- saldo total sebelum dan sesudah migrasi sama per toko/produk/batch;
- Desktop, Android, JSP, dan ZK menghasilkan hasil bisnis yang sama;
- kode server lulus kompilasi Java 1.7;
- session native tidak bocor dan tidak meninggalkan `idle in transaction`.

### 15.3 UAT beban

- 50.000 produk, 5.000 lokasi, 1.000.000 movement, 100 pengguna konkuren;
- pencarian/paging p95 < 2 detik pada jaringan normal;
- scan-confirm p95 < 1 detik di LAN;
- posting transfer 1.000 baris tidak timeout dan dapat dilanjutkan;
- laporan besar menjadi background job, tidak menahan request HTTP;
- uji race untuk reservasi dan penerimaan pada produk/lokasi yang sama.

## 16. Risiko dan mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Ledger lama dan baru berbeda | laporan/stok salah | satu posting service, rekonsiliasi otomatis, cutover bertahap |
| Reuse `sirs.Gudang` tidak cocok | coupling domain | audit usage, adapter/migrasi ke model netral |
| Double/precision qty | selisih kecil berulang | BigDecimal/numeric dan aturan pembulatan UOM |
| Penerimaan/transfer diulang | stok ganda | idempotency key + unique constraint + state transition atomik |
| Batch/serial tidak konsisten | traceability gagal | constraint scoped dan validasi server |
| Opname saat transaksi berjalan | selisih semu | snapshot/freeze + movement-after-snapshot |
| Laporan besar memblokir server | timeout/koneksi habis | async job, pagination, projection, index |
| Hak akses hanya di UI | kebocoran data | filter tenant/gudang dan permission di server |
| Jurnal tidak sinkron | nilai persediaan salah | posting/reversal terikat movement + rekonsiliasi |

## 17. Keputusan yang perlu disetujui sebelum coding

1. Apakah `sirs.Gudang` resmi dijadikan master gudang enterprise atau dibuat master
   netral baru?
2. Apakah fase pertama hanya untuk varian Inventory & Sales/eBisnis, atau langsung
   aktif juga pada Al-Bahjah dan Apotik?
3. Metode valuasi awal: Average, FIFO, atau keduanya per kategori?
4. Kapan penerimaan menambah stok: setelah receipt atau setelah QC?
5. Apakah transaksi antar toko merupakan transfer internal satu entitas atau transaksi
   antar satuan kerja dengan jurnal antar unit?
6. Apakah serial number dibutuhkan pada fase pertama?
7. Apakah offline mutation diizinkan untuk receipt/transfer/opname, atau hanya cache
   read dan draft lokal?
8. Batas nominal/selisih yang memerlukan approval supervisor.

## 18. Rekomendasi langkah berikutnya

Sebelum membuat menu, lakukan **Fase 0** dalam satu pekerjaan terpisah: audit seluruh
write path stok, putuskan master gudang/lokasi, dan tetapkan kontrak stok/valuasi.
Setelah delapan keputusan di atas disetujui, implementasi dapat dimulai dari master
Gudang & Lokasi serta ledger/proyeksi tanpa mengganggu fungsi lama.

Dokumen ini sengaja tidak menetapkan nama tabel final atau mengubah kode karena
keputusan ownership gudang dan metode valuasi akan memengaruhi seluruh desain.
