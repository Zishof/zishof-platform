# Handover POS Apotik & eMedik — 2026-08-12

Untuk melanjutkan di komputer/sesi lain. Semua **sumber sudah di git** (bukan di svn).

## Status repo saat handover (semua clean & ter-push)

| Repo | Lokasi | Branch | HEAD | Remote |
|---|---|---|---|---|
| AIS (server Java) | `C:\opt\AIS\ais\src\main` | `feat/new-ui-rbac-role-user` | `ab3c9a81` | github.com/Zishof/AIS |
| Flutter (monorepo) | `C:\opt\CodeBaseDesktopDanMobile` | `main` | `63d0021` | github.com/Zishof/zishof-platform |

Di mesin baru: `git clone` / `git pull` kedua repo dari branch di atas. **Server AIS auto-sync dari git** branch `feat/new-ui-rbac-role-user` (branch ini = lini deploy, `main` AIS unrelated-history/vestigial — lihat "Terblokir").

## Yang SELESAI & LULUS (POS Apotik/eMedik)
- **FASE A/B/C** semua **LULUS E2E** di demo.ecampus.id (evidence: `docs/pos-apotik-emedik/evidence/fase-a4-LULUS.md`, `fase-c-LULUS.md`).
  - A (Kasir): tebus resep, FEFO, **tolak jual kedaluwarsa**, register obat terkendali, LASA, idempoten.
  - B (Persediaan): terima PBF, opname, retur, monitor batch.
  - C (Laporan): penjualan, obat terkendali, kedaluwarsa.
- **Rilis GitHub** (Zishof/zishof-platform): `apotik-v1.33.1` & `emedik-v1.33.1` (installer Win + APK). Rilis lama `apotik-v1.33.0`/`emedik-v1.31.0` sudah diberi banner "tersuperseti".
- **Update-checker varian-aware** (`packages/core_update` + `AppProductProfile.tagRilisPrefix`): apotik/emedik tarik rilis `apotik-v*`/`emedik-v*` sendiri. `flutter test` core_update lulus.
- **Signing scaffold**: Gradle sudah wired baca `apps/ebisnis/android/key.properties` (fallback debug). Template `key.properties.example` + panduan `docs/signing-rilis.md`. Keystore/cert = milik pemilik.
- **4 bug** ditemukan & diperbaiki lewat UAT nyata (role-menu MODUL_POS-only, `jenis_transaksi` NOT NULL, crud-grant via API, kolom `hasilpenghitungantotal` implicit-naming).

## Cara build ulang varian (mesin baru)
Di `apps/ebisnis` (butuh Flutter SDK, Android SDK, Inno Setup 6):
```bash
# Apotik (ganti apotik->emedik utk varian eMedik)
flutter build windows --release -t lib/main_apotik.dart --dart-define=EBISNIS_VARIANT=apotik
flutter build apk --release --flavor apotik -t lib/main_apotik.dart --dart-define=EBISNIS_VARIANT=apotik
# Installer (dari repo Inno Setup):
ISCC /DAppVersion=<x.y.z> installer/apotik.iss
```
**Penting:** kalau pubspec versi di-bump sesi paralel saat build, PATOK versi dgn
`--build-name=<x.y.z> --build-number=<n>` di kedua build agar exe+apk+installer+tag konsisten (masalah nyata di sesi ini: exe keluar 1.33.3 padahal installer 1.33.1).

## Server AIS (mesin baru)
- Compile: `mvn -o compile` di `C:\opt\AIS\ais` (ANT/-source 1.6, JDK-nya lihat catatan repo).
- Demo E2E: `https://demo.ecampus.id/ecampus/Api_eBisnis`, akun uji `demo` (password diketahui pemilik). Role uji `am` — SUDAH direstore (apotik keys off).
- **SIRS wajib ter-init** utk transaksi apotek: baris `sirs.kode_transaksi_medis` (AJ/BM/ADT/ADK/AR/BR). `InitSirs` TIDAK jalan di eCampus akademik → pakai aksi `apotik_provision_demo` (admin + token `SEED-DEMO-APOTIK` + hanya server tanpa item; idempoten, set ConstantValues live). Data uji `UJI-PCT`/`UJI-CDN` sengaja ditinggal di demo.

## TERBLOKIR / perlu keputusan pemilik
1. **PR AIS branch → main MUSTAHIL normal**: `feat/new-ui-rbac-role-user` (root `c98b5a15`) & `main` (root `396ff3e9`) **unrelated histories** — GitHub tolak PR. Branch ini lini deploy nyata; kalau mau jadi main, perlu strategi eksplisit (jadikan main baru / graft), JANGAN `merge --allow-unrelated-histories` (konflik masif).
2. **Code-signing produksi**: butuh keystore Android + sertifikat code-signing dari pemilik (belum ada). Scaffold siap.
3. **SVN**: WC `CodeBaseDesktopDanMobile` & `desktop-pos-electron` **TIDAK di-svn-commit** karena hanya berisi artefak build/cache (`.dart_tool/flutter_build/**`, `release/*.exe`, `win-unpacked/**`, `node_modules/`) + (Flutter) git-internals — bukan sumber. Semua SUMBER ada di git. Reconcile svn (svn:ignore build dirs) di mesin bersih terpisah, bukan bagian handover ini.
4. **⚠️ DISK PENUH** di mesin ini: `C:` ~0.45 GB free (475 GB used) akibat akumulasi build Flutter/Gradle. Build berikutnya di mesin INI bisa gagal (`ENOSPC`). Bersihkan: `flutter clean`, `~/.gradle/caches`, cache pub. (Mesin baru tidak terpengaruh.)

## Memori
Status proyek tercatat di memori `pos-apotik-emedik-status.md` (dan `MEMORY.md` index) — akan termuat otomatis di sesi berikutnya pada mesin dengan direktori memori yang sama.
