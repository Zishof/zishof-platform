# 00 — Baseline P0 (2026-08-11)

## Repo & branch (FACT_SOURCE, diverifikasi lokal)

| Repo | Path | Branch | HEAD | Remote |
|---|---|---|---|---|
| AIS (server Java) | `C:\opt\AIS\ais` (source `src\main`) | `feat/new-ui-rbac-role-user` | `cb09ed88` | github.com/Zishof/AIS.git |
| zishof-platform (Flutter) | `C:\opt\CodeBaseDesktopDanMobile` | `main` | `d86526f` | github.com/Zishof/zishof-platform.git |

Working tree AIS: 1 modifikasi asing (`src/ais/action/master/helper/util/PenjadwalanUtil.java`,
sesi paralel lain) — TIDAK disentuh pekerjaan ini. Working tree Flutter: bersih kecuali artefak
build untracked (APK, file transient kotlin).

## Build/test baseline (FACT_SOURCE)

| Perintah | Dari | Hasil |
|---|---|---|
| `mvn -o compile` | `C:\opt\AIS\ais` (pom.xml di ROOT repo, bukan `src\main`) | EXIT=0 (bersih) |
| `flutter analyze` | `apps\ebisnis` | 31 issue, SEMUA info/warning, 0 error |
| `flutter test` | `apps\ebisnis` | 1/1 lulus (hanya smoke test `widget_test.dart`) |

Failure existing: TIDAK ADA yang blocking. 31 info/warning analyze = utang gaya lama
(deprecated `withOpacity`/`Table.fromTextArray`, `sort_child_properties_last`, dst.) — bukan
tanggungan fase ini, dicatat agar tidak dianggap regresi baru.

Toolchain: Maven 3.9.11; Java source/target 1.8 (`pom.xml` `java.level=8`); Flutter dipin
`.fvmrc` = 3.27.4 (praktik build nyata memakai SDK global `C:\opt\flutter`); AGP 8.7.0,
Kotlin 2.1.0, compileSdk 36, minSdk 23. Versi app saat ini `1.30.0+53`.

## Titik integrasi server yang sudah diverifikasi (FACT_SOURCE)

- `/Api_eBisnis` → `ais.action.servlet.ApiEBisnis extends PosApi` (alias murni, web.xml:1721).
- Dispatcher: `PosApi.proses()` rantai if/else, fallback "Aksi tidak dikenal" di
  `PosApi.java:619-622` → titik sisip hook `prosesAksiTambahan`.
- Auth: Bearer token via `PosDeviceAuthApi.resolveDariRequest` (30 hari), CORS wildcard aman.
- Gate menu per-aksi: `bolehAksesActionKantin` (PosApi.java:1180-1267), default akhir
  `return true` → aksi `si_*` WAJIB diberi blok gate eksplisit sebelum baris 1266.
- RBAC: `Tbmrole` (PK String `roleId`, `roleName`, kolom JSON `ebisnisMenu`) +
  `EbisnisMenuKatalog` (katalog datar 28 kunci + pohon `ebisnis_menu_master.json`);
  `Tbmuser.hakAkses()` = SATU role aktif (jangan union 5 slot role).
- "Admin global" hari ini = `tbmuser.getPedagang()==null` (~30 lokasi di KantinHelper) —
  INILAH asumsi berbahaya yang digantikan resolver fail-closed (FND-006).
- Supplier: `library.Penyedia` (dipakai `PengadaanFaktur.supplier`) + aksi
  `penyedia_list/penyedia_simpan`, `kulakan_faktur_simpan/list/detail` (semua sudah live).
- Customer: `koperasi.AnggotaKoperasi` (kode/nama/alamat/telp/hp/limitKredit) — TANPA field
  termin/area/sales → butuh profil extension (P2).
- Piutang customer: TIDAK ada tabel ledger; mutasi hutang dihitung on-the-fly (UNION ALL
  pembelian ber-flag masukSebagaiHutang vs `PembayaranHutang`) → ledger piutang per-sales
  harus didesain baru (P4/P5).
- Sesi kas: `inventory.SesiKasKasir` + `sesi_kas_status/buka/tutup` (idempoten by `kode`).
- Stok: `StokKantinUtil.formulaStokSql` 8 suku, DUA salinan (SQL + Java) wajib sinkron;
  `MutasiStokToko` = pola terdekat utk stok mobil sales (tapi hanya kenal Toko↔Toko).
- Jurnal/COA: `akunting.Akun` + `akunting.Transaksi` (double entry, statusPosting);
  laporan: `LaporanKatalogData` + `LaporanKantinUtil` (id `akn_laba_rugi`, `fin_laba_rugi`).
- Envers aktif (schema `new_audit`, suffix `__audit`); PERINGATAN pom: hbm2ddl update tidak
  selalu menyinkronkan kolom baru ke tabel audit existing.
- Namespace `si_*` / SalesInventory / SuratPerintah / NotaSales: 100% KOSONG (tidak ada bentrok).

## Titik integrasi Flutter yang sudah diverifikasi (FACT_SOURCE)

- Mekanisme varian SUDAH ADA (Al-Bahjah): `lib/app_variant.dart` (`--dart-define=EBISNIS_VARIANT`),
  `windows/variant.cmake` (deteksi base64 dari generated_config), `Runner.rc`/`main.cpp` ifdef,
  installer `.iss` per varian (`ebisnis.iss` AppId `…EBISN`, `albahjah.iss` AppId `…ALBH`).
- Belum ada: `bootstrap.dart`, `product_profile.dart`, `main_inventory_sales.dart`,
  flavor Android (build.gradle tanpa productFlavors; release masih debug-signing; label
  AndroidManifest hardcoded "ebisnis"), build script apa pun (semua manual).
- Menu = 2 registry (app_shell `MenuEBisnis` 21 nilai + `_kunciAksesMenu` + app_drawer
  hardcoded) — menu baru harus dirakit lewat registry ber-feature-group (P1) supaya tidak
  menambah duplikasi ketiga.
- Landing hardcode `KasirScreen` di `login_screen.dart:40-42` + `main.dart:283-285`.
- `Sesi` (sesi.dart) diisi dari aksi `konfigurasi` via `kasir_screen._terapkanKonfig` —
  belum ada actorType/permissions granular.
- `core_db` schema v3 (7 tabel, pola upgrade idempoten try/catch); `core_sync` = PLACEHOLDER
  KOSONG (Calculator template) padahal di-depend — implementasi nyata = FND-009 (P7).
- `core_update` memilih asset GitHub by keyword ternormalisasi: `inventory_sales` →
  `inventorysales`; nama asset rilis wajib memuat substring itu.

## Kesimpulan P0

Baseline SEHAT. Tidak ada blocker untuk memulai P1. Deviasi dari paket instruksi dicatat di
`02-decisions.md` (D-01 branch in-place). Keterbatasan sumber: video sistem legacy tidak
tersedia lokal (lihat `uat-required.md`).
