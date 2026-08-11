# Evidence P2 — Foundation master & inventory, layar 01–19 (2026-08-11/12)

## Commit (semua pushed)

| Repo | Commit | Isi |
|---|---|---|
| AIS | `c1644750` | si_supplier_*/si_customer_*/si_sales_* + entity SupplierInventoryProfile & CustomerInventoryProfile |
| AIS | `b74c36f7` | si_inventory_balance + si_inventory_ledger (SalesInventoryStokHelper) |
| AIS | `431c74c6` | HargaBeliSupplier + HargaJualCustomer + si_*_price_* + si_price_analysis |
| zishof-platform | `f29e93f`* | 3 layar master + Sesi.crudInventorySales + menu (*ikut membawa file staged sesi paralel — lihat catatan) |
| zishof-platform | `cc8083c` | persediaan_screen + kartu stok + menu |
| zishof-platform | `0b66b76` | harga_screen 3 tab + menu |

## Build & test yang DIJALANKAN

- `mvn -o compile` EXIT=0 pada 3 slice server (setelah tiap slice).
- `flutter analyze` 0 error di setiap slice (info-lint = pola baseline; angka akhir dicatat
  di pesan commit masing-masing). `flutter test` lulus.
- Build release PASCA seluruh layar P2 (dijalankan nyata, 2026-08-12):
  - `flutter build apk --release --flavor inventorySales -t lib/main_inventory_sales.dart
    --dart-define=...` → SUKSES 219.8s, `app-inventorysales-release.apk` (82.2MB).
  - `flutter build windows --release -t lib/main_inventory_sales.dart --dart-define=...`
    → SUKSES 86.4s (percobaan pertama gagal LNK1104 karena `ebisnis.exe` build folder
    sedang DIJALANKAN pihak lain — tidak dimatikan paksa; diulang setelah proses selesai).

## Cakupan per layar (ringkas — detail: 01-gap-ledger.csv)

- SCR-01..07 (master Supplier/Customer/Sales): server+Flutter LENGKAP (list search-first,
  detail tanpa efek data, CRUD, kode legacy terkunci, duplikat ditolak, nonaktif beralasan,
  audit info, unsaved-change guard, otorisasi granular 2 lapis).
- SCR-08 (Persediaan & Kartu Stok): LENGKAP — saldo ledger per periode (Awal/Masuk/Keluar/
  Opname/Akhir/nilai/min) + kartu stok 8 suku + saldo berjalan.
- SCR-09/10 (Opname + cetak): REUSE StokOpnameScreen existing (sudah punya Download/Upload
  Excel + Cetak PDF dari fitur terdahulu); filter stok-mobil-sales menyusul P5.
- SCR-11/13/17/18/19 (Harga): LENGKAP sisi master berversi + analisis margin; approval
  berjenjang & impor template menyusul.
- SCR-12/14/15/16 (cetak/preview/ekspor): DITUTUP di commit `50651f2` (2026-08-12) —
  `cetak_util.dart` baru (CetakUtilIs: PDF pw.MultiPage dgn konteks toko/pengguna/waktu/
  parameter + CSV pola FilePicker); layar Persediaan & Harga dapat tombol Cetak PDF +
  Ekspor CSV (harga dgn dialog "Jual Saja"/"Sertakan Harga Beli"); data diambil penuh via
  loop paging `_ambilSemua`. Preview = dialog print OS (`Printing.layoutPdf`).
- MIG-001 Impor DBF (commit AIS `aaf825b5` + zishof `50651f2`, 2026-08-12): aksi
  `si_import_legacy` (upsert idempoten by kode legacy, existing tidak ditimpa, saldo STOK
  jadi StokOpname migrasi, otorisasi PEMILIK/ADMIN ditegakkan server) + tab ke-6 "Impor
  DBF" di Konfigurasi — kondisional HANYA varian IS + login Pemilik Usaha Sales/Inventory
  (permintaan eksplisit user); parser DBF murni Dart (`dbf_parser.dart`) diverifikasi
  terhadap 28 berkas arsip nyata `5-Inventory` (struktur field STOK/SUPPLIER/CUSTOMER/
  SALES/masterbl/masterjl dibaca langsung dari byte header aslinya).

## Catatan insiden (2026-08-11)

Commit `f29e93f` ikut membawa pekerjaan sesi paralel yang sedang ter-stage di repo bersama
(tab_screensaver dkk.) — tidak ada data hilang (semua ter-commit utuh & pushed), hanya
menumpang pesan commit. Mitigasi diterapkan sejak itu: `git commit -F <msg> -- <pathspec>`
eksplisit di semua commit berikutnya.

## Batasan (jujur)

1. UAT runtime seluruh layar menunggu deploy server (commit AIS di atas) + akun uji role —
   sama dengan blocker P1 (task #15).
2. DoD penuh per layar (offline/print/UAT) belum terpenuhi utk baris berstatus
   BACKEND_DONE/AUDITED — lihat kolom Blocker ledger; tidak ada yang diklaim DONE.
