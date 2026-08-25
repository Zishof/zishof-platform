# Fase implementasi menu dan hak akses Rantai Pasok

Tanggal: 25 Agustus 2026  
Status: Rencana implementasi yang dapat diturunkan ke coding

Dokumen ini melanjutkan:

- `2026-08-25-rancangan-terpadu-pengadaan-pergudangan-distribusi-produksi-pos.md`;
- `2026-08-25-arsitektur-menu-rantai-pasok.md`;
- `2026-08-25-gap-struktur-tabel-pergudangan.md`.

Fokus dokumen ini adalah urutan implementasi menu baru, kontrak hak akses, dan
Definition of Done. Seluruh menu baru harus mengikuti mekanisme hak akses
existing dan dikelola dari layar **Hak Akses Grup Pengguna** yang dikendalikan
oleh `ais.action.maintenance.TbmroleAction`.

## 1. Keputusan wajib

1. Pengguna dengan `Common.apakahAdmin() == true` boleh melihat dan menjalankan
   seluruh menu dan aksi yang sudah benar-benar tersedia.
2. Bypass admin hanya melewati pembatasan role. Admin tetap wajib melewati
   autentikasi, isolasi tenant/perusahaan/toko, status dokumen, validasi bisnis,
   idempotensi, dan audit trail.
3. Pengguna non-admin hanya boleh melihat menu dan menjalankan aksi yang
   diberikan melalui grup pengguna.
4. Pemeriksaan di UI hanya untuk kenyamanan. Keputusan otoritatif wajib dilakukan
   kembali di endpoint/service server.
5. Menu yang belum mempunyai layar atau service tidak boleh ditampilkan, termasuk
   kepada admin. Admin melihat semua fitur nyata, bukan placeholder.
6. Tidak membuat kolom Boolean baru pada `Tbmrole` untuk setiap menu.
7. Tidak membuat sistem izin baru yang paralel dengan mekanisme existing.

## 2. Fondasi existing yang dipakai

Hasil penelusuran kode menunjukkan fondasi berikut sudah tersedia:

| Komponen | Fungsi |
|---|---|
| `EbisnisMenuKatalog` | Sumber tunggal katalog menu, pemetaan platform, nilai default, dan izin aksi. |
| `Tbmrole.ebisnisMenu` | Penyimpanan JSON status menu dan aksi per grup pengguna. |
| `TbmroleAction` | Controller/layar untuk mengatur grup pengguna dan hak menu/aksi. |
| `Menu`, `job_has_menu`, `RolePrivilage` | Hak akses hybrid/legacy untuk route JSP/ZK dan snapshot menu lama. |
| `NewUiHybridMenuAccessService` | Penyusun snapshot hak menu untuk UI hybrid. |

Istilah “tabel `TbmroleAction`” pada kebutuhan ini diterapkan sebagai **master
pengaturan hak akses yang dikelola oleh class `TbmroleAction`**. Persistensi
utamanya tetap `Tbmrole.ebisnisMenu` dan relasi legacy yang sudah ada. Tidak perlu
membuat tabel baru bernama `TbmroleAction`, karena itu nama action/controller,
bukan model database.

Format existing yang dipertahankan:

```json
{
  "supervisor": false,
  "menu": {
    "warehouse_receipt": true,
    "warehouse_pick": true
  },
  "crud": {
    "warehouse_receipt": {
      "create": true,
      "update": true,
      "delete": false,
      "approve": true,
      "reject": true
    }
  }
}
```

## 3. Kontrak admin dan role

### 3.1 Helper kanonik

Kode baru tidak boleh mempunyai variasi aturan admin sendiri-sendiri:

- konteks pengguna aktif memakai `Common.apakahAdmin()`;
- pemeriksaan terhadap objek pengguna eksplisit memakai helper existing yang
  ekuivalen, saat ini `Common.getApakahAdminLain(tbmuser)`;
- kedua jalur harus menghasilkan arti bisnis yang sama.

Pola server-side Java 1.7:

```java
private boolean bolehAksi(Tbmuser user, String menu, String aksi) {
    if (user == null) {
        return false;
    }
    if (Common.getApakahAdminLain(user)) {
        return true;
    }
    Tbmrole role = user.hakAkses();
    if (role == null || Boolean.FALSE.equals(role.getAktif())) {
        return false;
    }
    JSONObject akses = EbisnisMenuKatalog.urai(role.getEbisnisMenu());
    JSONObject daftarMenu = akses.optJSONObject("menu");
    if (daftarMenu == null || !daftarMenu.optBoolean(menu, false)) {
        return false;
    }
    return EbisnisMenuKatalog.bolehAksi(akses, menu, aksi);
}
```

Untuk modul baru, role kosong harus **fail-closed**. Kompatibilitas role lama
ditangani oleh migrasi eksplisit, bukan dengan mengizinkan semua pengguna tanpa
role.

### 3.2 Batas bypass admin

| Pemeriksaan | Admin boleh bypass? |
|---|---:|
| Menu aktif untuk role | Ya |
| Aksi create/update/approve dan seterusnya untuk role | Ya |
| Tenant/perusahaan yang sedang aktif | Tidak |
| Toko/gudang yang berada di tenant tersebut | Tidak |
| Dokumen sudah dibatalkan/ditutup | Tidak |
| Kuantitas negatif atau melebihi stok tanpa kebijakan | Tidak |
| Idempotency key/dokumen ganda | Tidak |
| Periode akuntansi sudah ditutup | Tidak |
| Audit alasan koreksi/reversal | Tidak |

### 3.3 Visibilitas lintas platform

Desktop, Android, JSP, dan ZK harus menerima keputusan akses dari katalog dan
endpoint yang sama. Nama kunci harus identik pada:

- `EbisnisMenuKatalog`;
- `ebisnis_menu_master.json`;
- route Desktop;
- peta layar Android;
- menu JSP/ZK;
- pemeriksaan endpoint API.

## 4. Perluasan aksi granular

Katalog existing baru mengenal `create`, `update`, `delete`, `approve`, dan
`reject`. Pergudangan membutuhkan aksi bisnis yang tidak aman bila disamakan
dengan `update`.

Katalog aksi yang ditambahkan secara bertahap:

| Kelompok | Aksi |
|---|---|
| Data | `view`, `create`, `update`, `delete` |
| Workflow | `submit`, `approve`, `reject`, `cancel`, `reopen`, `close` |
| Persediaan | `reserve`, `release`, `receive`, `putaway`, `pick`, `pack`, `issue`, `count`, `adjust` |
| Posting | `post`, `reverse` |
| Distribusi | `assign`, `dispatch`, `track`, `confirm_delivery` |
| Dokumen | `print`, `export`, `upload_attachment` |
| Administrasi | `configure` |

`TbmroleAction` harus merender aksi dari metadata katalog per menu, bukan membuat
kolom UI hard-coded untuk seluruh aksi. Menu sederhana tetap hanya mendapat aksi
yang relevan.

Kompatibilitas:

1. lima aksi existing tidak diubah;
2. aksi baru pada role lama dimigrasikan berdasarkan template role;
3. aksi berisiko tinggi (`post`, `reverse`, `adjust`, `dispatch`, `close`) default
   nonaktif untuk non-admin;
4. hasil migrasi disimpan eksplisit agar perilaku tidak berubah saat versi kode
   berikutnya menambah aksi baru.

## 5. Katalog menu dan aksi minimum

| Kunci menu | Label | Aksi minimum |
|---|---|---|
| `supply_chain_control_tower` | Kendali Rantai Pasok | view, export |
| `replenishment_request` | Permintaan Stok Outlet | view, create, update, delete, submit, approve, reject, cancel |
| `replenishment_allocation` | Alokasi & Reservasi | view, reserve, release, approve |
| `replenishment_shortage` | Kekurangan / Backorder | view, update, submit |
| `outlet_local_purchase` | Pembelian Lokal Outlet | view, create, submit, approve, reject, cancel |
| `warehouse_dashboard` | Dashboard Gudang | view, export |
| `warehouse_receipt` | Penerimaan Barang | view, create, update, receive, reject, post, reverse, print |
| `warehouse_qc` | Pemeriksaan & QC | view, create, update, approve, reject, release |
| `warehouse_putaway` | Putaway | view, create, assign, putaway, cancel |
| `warehouse_inventory` | Posisi Persediaan | view, export |
| `warehouse_reservation` | Reservasi Gudang | view, reserve, release |
| `warehouse_pick` | Picking | view, create, assign, pick, cancel, print |
| `warehouse_pack` | Packing | view, pack, reopen, print |
| `warehouse_issue` | Goods Issue | view, issue, post, reverse, print |
| `warehouse_transfer` | Transfer Lokasi | view, create, submit, approve, issue, receive, cancel |
| `warehouse_count` | Stok Opname & Cycle Count | view, create, assign, count, approve, post |
| `warehouse_adjustment` | Penyesuaian Stok | view, create, approve, reject, post, reverse |
| `warehouse_quarantine` | Karantina & Release | view, create, release, reject |
| `warehouse_vendor_return` | Retur Vendor | view, create, submit, approve, issue, cancel |
| `distribution_plan` | Rencana Distribusi | view, create, update, approve, cancel |
| `transfer_order` | Transfer Order | view, create, update, submit, approve, cancel, print |
| `delivery_order` | Delivery Order | view, create, update, approve, release, cancel, print |
| `freight_order` | Freight Order | view, create, update, assign, approve, cancel, print |
| `shipment` | Shipment | view, create, assign, dispatch, track, close, cancel, print |
| `proof_of_delivery` | Proof of Delivery | view, confirm_delivery, reject, upload_attachment |
| `outlet_receipt` | Penerimaan Outlet | view, receive, reject, post, print |
| `outlet_return` | Retur Outlet | view, create, submit, approve, issue, receive, cancel |
| `production_bom` | BOM / Resep | view, create, update, delete, approve |
| `production_order` | Production Order | view, create, update, submit, approve, release, close, cancel |
| `production_material_issue` | Pengeluaran Bahan | view, create, issue, reverse |
| `production_receipt` | Penerimaan Hasil Produksi | view, create, receive, post, reverse |
| `production_variance` | Yield, Waste & Variance | view, approve, post, export |
| `quality_traceability` | Ketertelusuran Lot | view, export |
| `quality_recall` | Recall Produk | view, create, submit, approve, close |

Kunci final harus diselaraskan dengan node existing dalam
`ebisnis_menu_master.json`; daftar di atas adalah kontrak kapabilitas, bukan izin
untuk membuat route duplikat.

## 6. Fase implementasi

### Fase 0 — Baseline dan penguncian kontrak

Pekerjaan:

- inventaris route, API, tabel, status dokumen, dan permission existing;
- petakan kunci lama ke pohon menu baru;
- tetapkan kamus status dan idempotency key;
- bekukan kontrak relasi PR, PO, BAST, tagihan, pembayaran, dan ledger stok.

Selesai bila tidak ada dua sumber kebenaran untuk dokumen atau saldo yang sama.

### Fase 1 — Fondasi menu dan keamanan

Pekerjaan:

- daftarkan menu tersedia di `EbisnisMenuKatalog` dan
  `ebisnis_menu_master.json`;
- perluas metadata aksi granular;
- perbarui `TbmroleAction` untuk mengatur menu dan aksi baru;
- terapkan bypass `Common.apakahAdmin() == true` secara konsisten;
- buat guard server-side tunggal;
- lakukan invalidasi cache/menu snapshot setelah role disimpan;
- sinkronkan Desktop, Android, JSP, dan ZK.

Definition of Done:

- admin melihat seluruh menu yang tersedia;
- non-admin hanya melihat menu yang diizinkan;
- pemanggilan API langsung tetap ditolak bila izin tidak ada;
- perubahan role berlaku tanpa login ulang yang tidak perlu;
- tenant lain tidak pernah dapat diakses oleh bypass admin role.

### Fase 2 — Master data rantai pasok

Menu:

- Gudang, zona, lokasi, dan bin;
- item supply chain dan pemetaan ke Produk/Asset;
- UOM dan konversi;
- batch/lot/kedaluwarsa;
- supplier, carrier, kendaraan, rute;
- kebijakan min-max/reorder;
- BOM/resep.

Hak kritis: configure, create, update, delete, approve.

### Fase 3 — Perencanaan dan Replenishment

Alur:

1. outlet membuat permintaan stok;
2. sistem menghitung available/reserved/in-transit;
3. stok tersedia dialokasikan dari gudang;
4. shortage dikonsolidasikan menjadi usulan PR;
5. pembelian lokal outlet menjadi jalur pengecualian berpersetujuan.

Tidak boleh membuat PO atau mutasi stok langsung pada fase ini.

### Fase 4 — Inbound Pergudangan

Alur:

1. jadwal kedatangan/ASN;
2. goods receipt terhadap PO/BAST;
3. QC dan karantina;
4. putaway ke lokasi;
5. posting ledger stok idempoten.

BAST supplier mengesahkan penerimaan, sedangkan goods receipt mencatat kejadian
fisik. Keduanya ditautkan, bukan saling menggandakan stok.

### Fase 5 — Persediaan internal Gudang

Mencakup posisi stok, reservasi, transfer lokasi, kartu stok, aging, batch/FEFO,
cycle count, opname, adjustment, rusak/hilang, disposal, dan rekonsiliasi.

Setiap adjustment dan reverse memerlukan alasan, persetujuan, serta audit before/
after.

### Fase 6 — Outbound, Distribusi, dan Pengiriman

Alur:

1. alokasi permintaan outlet;
2. transfer order;
3. picking dan packing;
4. delivery order/surat jalan;
5. freight order bila memakai jasa angkut;
6. shipment dan dispatch;
7. tracking dan Proof of Delivery.

Goods issue memindahkan stok ke `in_transit`, bukan langsung dianggap diterima
outlet.

### Fase 7 — Penerimaan dan retur Outlet

Outlet mencatat penerimaan per DO/lot, selisih, kerusakan, penolakan, BAST
internal, dan retur. Stok outlet bertambah hanya dari penerimaan yang berhasil
diposting.

### Fase 8 — Produksi

Mencakup BOM/resep berversi, production order, reservasi dan issue bahan, WIP,
receipt barang jadi, yield, waste, variance, rework, batch genealogy, dan close.

### Fase 9 — Mutu dan Ketertelusuran

Mencakup QC inbound, karantina/release, non-conformance, CAPA, cold chain,
traceability supplier sampai POS, dan recall.

### Fase 10 — Keuangan dan Akuntansi

Integrasi:

- three-way matching PO–receipt–invoice;
- tagihan freight;
- persediaan, in-transit, WIP, barang jadi, HPP, variance;
- reversal dan tutup periode;
- tautan drill-down ke dokumen fisik.

Tidak membuat jurnal dari UI dashboard. Posting harus melalui service idempoten.

### Fase 11 — Control Tower dan laporan

Menyediakan KPI fill rate, stockout, lead time, dock-to-stock, picking accuracy,
OTIF, selisih kirim/terima, inventory accuracy, aging, yield, waste, dan variance.
Semua angka wajib clickable ke dokumen sumber dan dapat diekspor sesuai izin.

### Fase 12 — Paritas platform dan rollout

Urutan:

1. kontrak API dan guard server;
2. Desktop;
3. JSP/ZK untuk operasi back-office;
4. Android untuk scan, receive, pick, POD, dan approval;
5. UAT pilot satu gudang dan satu outlet;
6. rekonsiliasi stok/keuangan;
7. rollout bertahap per lokasi.

## 7. Template role awal

| Role | Cakupan utama |
|---|---|
| Admin | Semua menu/aksi tersedia melalui bypass kode. |
| Supply Chain Planner | Dashboard, replenishment, alokasi, shortage, forecast. |
| Purchasing | Pengadaan existing dan referensi shortage; tanpa posting stok. |
| Warehouse Receiver | Receipt, QC awal, putaway; tanpa adjustment/reverse. |
| Warehouse Operator | Pick, pack, transfer lokasi, count. |
| Warehouse Supervisor | Approval, post, adjustment, reverse, close. |
| Dispatcher | DO, Freight Order, Shipment, dispatch, tracking. |
| Outlet Receiver | Receive, reject, BAST internal, retur outlet. |
| Production Operator | Issue bahan, receipt hasil, pencatatan yield/waste. |
| Production Supervisor | Approve/release/close production order dan variance. |
| Quality Control | QC, quarantine, release/reject, traceability, recall. |
| Finance AP | Invoice/tagihan/matching; tanpa mutasi stok. |
| Accounting | Posting jurnal, reversal, rekonsiliasi; view dokumen fisik. |
| Auditor | View dan export seluruh dokumen sesuai tenant; tanpa mutasi. |

Template hanya mempercepat setup. Nilainya tetap disimpan eksplisit pada grup
pengguna melalui `TbmroleAction`.

## 8. Migrasi hak akses

1. backup nilai `Tbmrole.ebisnisMenu`;
2. tambah katalog menu/aksi tanpa menghapus kunci lama;
3. petakan role existing ke template yang paling dekat;
4. aksi berisiko tinggi default false untuk non-admin;
5. simpan hasil migrasi eksplisit;
6. validasi jumlah role/menu/aksi sebelum dan sesudah migrasi;
7. invalidasi cache hak akses;
8. sediakan rollback data JSON;
9. catat perubahan di audit log.

Tidak perlu menulis baris “allow all” untuk setiap admin. Hak penuh admin berasal
dari pemeriksaan `Common.apakahAdmin()`, sehingga menu baru otomatis ikut terlihat
setelah benar-benar tersedia.

## 9. Matriks UAT hak akses

| Kasus | Hasil yang diwajibkan |
|---|---|
| Admin membuka seluruh platform | Semua menu tersedia tampil dan dapat dibuka. |
| Admin mencoba tenant lain | Ditolak oleh isolasi tenant. |
| Non-admin tanpa menu | Menu tersembunyi dan API mengembalikan forbidden. |
| Non-admin view saja | Data tampil, seluruh mutasi ditolak. |
| Operator tanpa approve | Tombol approve tidak tampil dan API approve ditolak. |
| Role dicabut saat sesi aktif | Cache diperbarui; request berikutnya ditolak. |
| Endpoint dipanggil manual | Keputusan sama dengan UI. |
| Dokumen dipost dua kali | Request kedua idempoten/tidak membuat mutasi ganda. |
| Admin memposting dokumen invalid | Tetap ditolak oleh validasi bisnis. |
| Desktop/Android/JSP/ZK | Kunci menu dan keputusan akses identik. |
| Role lama setelah migrasi | Menu existing tidak hilang tanpa keputusan migrasi. |
| Audit | Aktor, role, tenant, menu, aksi, dokumen, waktu, dan hasil tercatat. |

## 10. Urutan coding yang disarankan

1. Fase 0 dan 1 harus selesai lebih dahulu.
2. Implementasikan vertical slice Replenishment → Receipt → DO → Outlet Receipt
   untuk satu jenis item.
3. Uji ledger dan rekonsiliasi sebelum memperluas layar.
4. Tambahkan produksi setelah transfer gudang stabil.
5. Tambahkan quality/recall setelah lot genealogy tersedia.
6. Control Tower terakhir karena bergantung pada data transaksi yang sudah benar.

Dengan urutan ini, penambahan banyak menu tidak menghasilkan banyak silo. Semua
menu tetap memakai katalog izin, service, dokumen, ledger, dan audit yang sama.
