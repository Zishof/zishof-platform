# UAT Runtime — MitraInap Langkah 4 (Room Charge POS Outlet → Folio Tamu)

**Tanggal:** 18 Agustus 2026 (malam, Asia/Jakarta)
**Lingkungan:** UAT lokal — PostgreSQL `localhost:5432/ais` + Tomcat UAT
(`CATALINA_BASE C:\opt\Codex-Worspace\.uat-tomcat-inventory`, port 18080, heap 10 GB).
**Build yang diuji:** working copy SVN `^/src` r77592 + perubahan Langkah 4
(HotelApiHelper `hotel_room_charge_lookup` / `periksaRoomChargePenjualan` /
`rekamRoomChargePenjualan`, hook di `KantinHelper.bayar`, gerbang PosApi) — **belum di-commit**
saat UAT ini dijalankan. Klien Flutter per perubahan `keranjang_screen.dart` (belum di-commit).

**Jalur uji:** harness Java in-process yang memanggil handler server PERSIS
(`HotelApiHelper.proses(...)` dan `KantinHelper.bayar(...)`) di atas
`HibernateUtil` + `hibernate.cfg.xml` UAT — kode bisnis dan transaksi DB yang
sama dengan yang dilalui PosApi. **Lapisan token Bearer TIDAK dicakup pass ini**
(butuh kredensial; pembuatan kredensial uji berada di luar wewenang sesi ini) —
lapisan itu sudah terbukti generik pada UAT Grup Produk 18 Agu 2026, dan
penolakan anonim diverifikasi ulang lewat HTTP (lihat bawah).

## Hasil: SELURUH 14 LANGKAH LULUS (`pass=14 fail=0`)

| # | Langkah | Hasil |
|---|---|---|
| 1 | Muat user `admin_1` (pedagang null → admin global) | ✓ |
| 2 | Pre-warm cache entity Toko/CaraPembayaran (padanan InitDataHelper boot webapp) | ✓ |
| 3 | `hotel_properti_simpan` | ✓ id terbit |
| 4 | `hotel_tipe_kamar_simpan` (harga dasar 250.000) | ✓ |
| 5 | `hotel_kamar_simpan` (kamar 101, VACANT) | ✓ |
| 6 | `hotel_tamu_simpan` | ✓ |
| 7 | `hotel_checkin` walk-in → stay IN_HOUSE + folio OPEN | ✓ |
| 8 | `hotel_room_charge_lookup` — tamu in-house terdaftar utk kasir outlet | ✓ |
| 9 | `bayar` POS (2×10.000, Tunai) + `hotel_menginap_id` → **status 00, `hotel_room_charge=TERCATAT`, `hotel_folio_id` benar** | ✓ |
| 10 | Panggilan posting kedua (retry pasca-commit) → **`IDEMPOTENT`**, beban tidak ganda | ✓ |
| 11 | Replay payload `bayar` yang sama (simulasi kiriman ulang outbox) → folio TETAP satu beban | ✓ (lihat temuan 1) |
| 12 | `hotel_folio_get` → saldo 20.000, tepat SATU baris `POS_CHARGE` referensi `POSSALE-<kodeUnik>` | ✓ |
| 13 | `hotel_checkout` bayar 270.000 (1 malam × 250.000 + 20.000 POS) → saldo akhir 0, folio CLOSED, kamar DIRTY | ✓ |
| 14 | Negatif: `bayar` baru menagih ke stay yang sudah CHECKED_OUT → **ditolak 91 "tamu sudah check-out" SEBELUM ada tulisan apa pun** (penjualan tidak tersimpan) | ✓ |

Verifikasi HTTP tambahan pada Tomcat UAT hidup: panggilan **anonim**
`hotel_room_charge_lookup` via `/ais/Data` ditolak rapi
`{"status":"90","description":"Pengguna tidak boleh akses"}` — gerbang auth servlet
di depan gerbang menu `kasir`.

## Temuan (bukan bug fitur, semuanya drift lingkungan UAT — sudah diperbaiki)

1. **DB UAT tidak punya constraint unik `pembelian_anggota_koperasi.kode`**
   (produksi punya, migrasi idempotency Fase 1.5). Replay `bayar` di UAT sempat
   menyisipkan baris penjualan kedua — **namun folio tetap satu beban** karena
   idempotensi `referensi` (`POSSALE-<kodeUnik>`) bekerja sebagai lapis kedua,
   persis tujuan desainnya (belt-and-suspenders terbukti). Constraint kini
   ditambahkan ke UAT (`pembelian_anggota_koperasi_kode_uniq`) setelah dedupe.
2. **Drift skema/cfg UAT** yang menghalangi jalur `bayar` terbaru (pola sama
   temuan UAT Grup Produk): mapping + tabel `ProdukBatch`/`MutasiProdukBatch`
   belum ada; `koperasi.kebijakan_retur` memakai nama kolom lama `oleh_id`
   (entity: `olehid`) dan tabel auditnya belum ada; kolom
   `detail_pembelian_cadangan` hilang di tabel utama+audit penjualan, serta
   `id_perangkat`/`sesi_kas_kasir` hilang di tabel audit penjualan (gotcha
   Envers: hbm2ddl tidak menyinkron kolom baru ke tabel audit lama — **catat
   utk deploy produksi berikutnya bila belum pernah ALTER audit tsb; produksi
   dengan hbm2ddl=update hanya aman utk tabel BARU**).
3. `.uat-classes` memuat `SesiKasUtil` lama → `NoSuchMethodError
   normalisasiIdPerangkat` dari KantinHelper baru; kelas segar dideploy.

## Penyiapan lingkungan yang dilakukan pass ini

- 8 kelas entity `hotel_*` + `HotelApiHelper` + `KantinHelper` + `PosApi` +
  `EbisnisMenuKatalog` + `SesiKasUtil` + `ProdukBatch`/`MutasiProdukBatch`
  dideploy ke `.uat-classes`.
- `hibernate.cfg.xml` UAT: +8 mapping hotel, +2 mapping batch produk (9 mapping
  SVN lain — vendor/reimbursement/obe — sengaja tidak ditambahkan; modul tak
  diuji dan kelasnya belum dideploy).
- Skema UAT dibuat MANUAL (konvensi UAT tanpa hbm2ddl): 8 tabel `public.hotel_*`
  + 8 `new_audit.hotel_*__audit` + 2 tabel batch + 2 auditnya
  (skrip: `uat-hotel-schema.sql`, padanan persis DDL hbm2ddl produksi).
- Data uji dibersihkan tuntas setelah lulus (hotel_* main+audit dikosongkan,
  penjualan `UAT-RC-%` + rinci + auditnya dihapus, stok produk uji 7423 utuh 100).
- Tomcat UAT di-restart dengan overlay final; boot bersih (tanpa SEVERE, tanpa
  bentrok nama entity `Kamar` — fix `HotelKamar` r77590 terbukti hidup
  berdampingan dengan `sirs.Kamar`).

## Yang TIDAK dicakup pass ini

- Lapisan token Bearer end-to-end utk aksi hotel (butuh kredensial UAT; lihat atas).
- Klik-through UI Flutter (kontrol "Tagihkan ke Kamar" di keranjang) terhadap
  server hidup — kontrak aksi terkunci di `keranjang_screen.dart`
  (`hotel_room_charge_lookup`, field `hotel_menginap_id`/`hotel_properti_id`).
- Jalur role non-admin dgn kunci menu `kasir` sungguhan (gerbang diverifikasi
  lewat inspeksi `bolehAksesActionKantin` + penolakan anonim HTTP).
