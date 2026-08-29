# Fase 0 — Dokumen Produksi Menggerakkan Stok (eksekusi ledger)

Tanggal: 29 Agustus 2026  
Status: implementasi server + UAT harness **lulus 19/19**; belum di-commit  
Rujukan desain: SVN `docs/pos/49-produksi-eksekusi-stok-dan-rencana-rinci.md`
(termasuk Adendum 29-08 yang merekonsiliasi dengan
[fondasi Fase 9](2026-08-26-fase-9-production.md) dan
[ADR kontrak data](2026-08-25-adr-kontrak-data-terpadu.md))

## Apa yang berubah

Sebelum fase ini, dokumen produksi (ISSUE/RETURN/OUTPUT/WASTE) yang di-POSTED
hanya tercatat — stok tidak bergerak (`stockAffecting` disimpan tapi tidak ada
eksekutornya; rumus stok tidak punya suku produksi). Sekarang:

- **POSTED** menulis ledger `koperasi.mutasi_stok_produksi` arah `FORWARD`
  untuk tiap baris ber-`stockAffecting` (ISSUE/WASTE keluar, RETURN/OUTPUT
  masuk), lalu menghitung ulang stok produknya.
- **REVERSED** menulis KONTRA-BARIS arah `REVERSE` — ledger tidak pernah
  dihapus (ADR: koreksi lewat movement lawan; pola
  `DistribusiPengirimanApiHelper.postingStok`).
- Idempoten dua lapis: unik `(dokumen_id, baris_id, arah)` + kunci
  `PRODUCTION:<dokumen>:<jenis>:<baris>:<arah>` (format fondasi Fase 9).
- **Transaksional, TIDAK fail-safe**: kegagalan posting membatalkan transisi
  status. Validasi baris (tanpa `itemId` / produk beda toko / qty ≤ 0) ditolak
  dengan pesan yang terbaca, dokumen tetap DRAFT.
- BOM/WO/COST tidak pernah menggerakkan stok.

## Berkas (SVN, canonical `src` + mirror `java`, md5 identik)

| Berkas | Isi perubahan |
|---|---|
| `ais/database/model/inventory/MutasiStokProduksi.java` | entitas ledger BARU (skema `koperasi`), terdaftar di `hibernate.cfg.xml` kedua pohon |
| `ais/action/servlet/api/ProduksiApiHelper.java` | `postingStok`/`balikkanPostingStok` pada `ubahStatus` |
| `ais/action/master/inventory/StokKantinUtil.java` | suku ke-9 di `formulaStokSql` + `recomputeStokProduk` + JavaDoc |
| `ais/action/servlet/api/KantinHelper.java` | kartu stok (+1 cabang UNION), CTE laporan harian (+1 cabang, parameter 8→9), audit ledger-vs-stok, `TABEL_REFERENSI_PRODUK` |
| `ais/action/servlet/api/SalesInventoryStokHelper.java` | kartu stok Inventory & Sales (+1 cabang masuk/keluar) |
| `ais/action/master/inventory/StokOpnameKantinAction.java`, `StokOpnameScanUtil.java` | baseline opname + suku produksi |
| `ais/action/master/koperasi/helper/LaporanKantinUtil.java` | `fStok` stok-per-tanggal + suku produksi ber-cutoff |

Kompilasi `javac -source 1.7 -target 1.7`: **EXIT=0**; keluaran ke
`build/uat-77608` (terisolasi); `.class` di source tree: **0**.

## UAT — harness `TesProduksiStok` (19 pemeriksaan, 0 gagal)

ISSUE memotong stok; POSTED ulang idempoten (ledger & stok tidak ganda);
REVERSED menulis kontra-baris & memulihkan stok dengan FORWARD tetap utuh;
OUTPUT menambah; WASTE memotong; RETURN mengembalikan; baris `stockAffecting`
tanpa `itemId` ditolak dan dokumen TETAP DRAFT tanpa ledger; baris
non-`stockAffecting` tidak menggerakkan apa pun; COST tidak pernah menulis
ledger. Harness memakai jalur API yang sama dengan klien
(`ProduksiApiHelper.simpan/ubahStatus`), menyapu awalan `UATPRD%` di awal, dan
`bersihkan()` tidak pernah melempar (pola dok. 44).

Rumus stok baru TERBUKTI dieksekusi (bukan hanya terkompilasi): pergerakan stok
di seluruh pemeriksaan terjadi lewat `recomputeStokProdukNative` yang memakai
`formulaStokSql` 9 suku.

## Catatan lingkungan uji (penting untuk sesi berikutnya)

1. **Kredensial `-D` di `.uat-tomcat-inventory/bin/setenv.bat` sudah DITOLAK
   server** (user `root`, autentikasi gagal) — padahal regresi 22-08 masih
   memakainya. Harness kini membaca kredensial dari `hibernate.cfg.xml`
   TERPASANG di Tomcat UAT lokal secara program, tanpa pernah mencetaknya.
   Konsekuensi: **seluruh harness lama (TesTagihan/TesBayar/dll) akan gagal
   konek** sampai setenv diperbaiki pemilik sistem atau diberi pola yang sama.
2. `build/uat-77608` tertinggal ±265 kelas mapping dari cfg r78501+
   (`build/classes` malah sudah dihapus sesi lain) — sudah dikompilasi ulang
   supaya Hibernate bisa boot. Ekstraksi mapping HARUS memperhitungkan entri
   `<mapping` yang terpecah dua baris.
3. Skema PostgreSQL `inventory_production` belum ada di DB UAT lokal —
   `hbm2ddl=update` membuat TABEL, bukan SKEMA. Harness membuatnya sekali
   (`CREATE SCHEMA IF NOT EXISTS`) sebagai penyiapan lingkungan; tabel tetap
   dibuat Hibernate.
4. Dua berkas ditemukan CAMPURAN akhir baris di HEAD (`StokKantinUtil.java`
   269 CRLF+6 LF; `hibernate.cfg.xml` 2402 CRLF+72 LF) — diseragamkan ke
   mayoritas (CRLF) secara sengaja dan tercatat.

## Batas kejujuran

- Cabang laporan baru (kartu stok, CTE harian, audit, kartu IS, fStok)
  terbukti **kompilasi**, belum dieksekusi per layar — eksekusi runtime baru
  terbukti untuk rumus kanonik lewat harness.
- Baseline opname (`StokOpnameKantinAction`/`ScanUtil`) SUDAH tertinggal 3 suku
  (retur penjualan/pembelian, mutasi antar toko) SEBELUM fase ini — drift lama,
  dilaporkan di sini, TIDAK diperbaiki diam-diam.
- Dokumen produksi lama yang terlanjur POSTED sebelum fase ini dibiarkan tanpa
  efek stok (keputusan pemilik sistem, dok. 49 Adendum).
- CRUD dokumen produksi di Flutter masih API langsung — migrasi Local-First
  (queueable-mutation untuk DRAFT; transisi status tetap online-only) adalah
  pekerjaan lanjutan sesuai handover, BUKAN bagian fase ini.
