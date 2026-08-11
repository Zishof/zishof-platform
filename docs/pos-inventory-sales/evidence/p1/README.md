# Evidence P1 — Varian, bootstrap, shell, role (2026-08-11)

## Commit

| Repo | Commit | Isi |
|---|---|---|
| AIS | `1d7a82dc` (branch feat/new-ui-rbac-role-user, pushed) | hook prosesAksiTambahan + ApiEBisnis dispatcher + EbisnisActorContextResolver + seed role + entity SalesInventory + 16 kunci menu + gate si_ |
| zishof-platform | (commit P1 flutter — lihat git log setelah file ini) | AppProductProfile/bootstrap/main_inventory_sales + Beranda IS + Sesi aktor + Windows variant + iss + flavor Android + wrapper build |

## Build & test yang DIJALANKAN (bukan klaim)

| Perintah | Hasil |
|---|---|
| `mvn -o compile` (C:\opt\AIS\ais) | EXIT=0 |
| `flutter analyze` | 0 error (2 warning unnecessary_cast = baseline lama, bukan dari perubahan ini) |
| `flutter test` | 1/1 lulus (smoke test tetap hijau setelah refactor main.dart → bootstrap.dart) |
| `flutter build windows --release -t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales` | SUKSES (67.3s) |
| `flutter build apk --release --flavor inventorySales -t lib/main_inventory_sales.dart --dart-define=...` | lihat baris APK di bawah |
| `flutter build apk --release --flavor ebisnis -t lib/main.dart` (regresi varian lama) | lihat baris APK di bawah |

## Verifikasi artefak Windows

`build\windows\x64\runner\Release\ebisnis_inventory_sales.exe` tercipta (post-build copy CMake),
VERSIONINFO hasil `#elif defined(EBISNIS_VARIANT_INVENTORY_SALES)` di Runner.rc:

```
ProductName     = eBisnis Inventory & Sales
FileDescription = eBisnis Inventory & Sales
InternalName    = ebisnis_inventory_sales
FileVersion     = 1.30.0+53
```

Deteksi varian CMake: token base64 `RUJJU05JU19WQVJJQU5UPWludmVudG9yeV9zYWxlcw==`
("EBISNIS_VARIANT=inventory_sales") di variant.cmake — terbukti bekerja karena copy exe +
VERSIONINFO varian hanya terjadi pada cabang itu.

Installer: `installer\inventory_sales.iss` — AppId `{B6C9E2D4-6C3A-4B0E-9C0D-1E3A5F0INVSL}`
(unik, tidak menimpa `…EBISN`/`…ALBH`), output `eBisnis-Inventory-Sales-Setup-<versi>.exe`,
exclude exe varian lain (fix dua-arah juga diterapkan ke albahjah.iss).

## Verifikasi APK (hasil build + `aapt dump badging` nyata)

| Build | Hasil | applicationId | Label |
|---|---|---|---|
| `--flavor inventorySales -t lib/main_inventory_sales.dart --dart-define=...` | SUKSES 93.3s → `app-inventorysales-release.apk` (81.4MB) | `id.zishof.ebisnis.inventorysales` versionCode 53 / 1.30.0 | `eBisnis Inventory & Sales` |
| `--flavor ebisnis -t lib/main.dart` (regresi varian lama) | SUKSES 116.5s → `app-ebisnis-release.apk` (81.4MB) | `id.zishof.ebisnis` versionCode 53 / 1.30.0 | `ebisnis` (identik label lama) |

Kedua APK bisa terpasang berdampingan (applicationId berbeda). Catatan build pertama gagal
1x: komentar XML `strings.xml` memuat `--` (dilarang XML) — diperbaiki, lalu hijau.

## Batasan verifikasi P1 (jujur, bukan DONE penuh)

1. **Login E2E 3 role** (DoD P1) membutuhkan server AIS yang SUDAH menjalankan commit
   `1d7a82dc` (seed role dieksekusi `ApiEBisnis.init()` saat servlet dimuat pasca-deploy)
   + akun uji ber-role `pemilik_sales_inventory` / `sales_keliling`. Restart/deploy Tomcat
   adalah wewenang operasional pemilik sistem (lihat catatan performa/restart di memori
   proyek) — TIDAK dilakukan sepihak dari sesi build ini. Jalur klien sudah teruji sampai:
   analyze/test hijau, build kedua platform sukses, dan Beranda IS menangani ketiga
   kemungkinan balasan server (aktor lengkap / server lama tanpa blok aktor / akses ditolak).
2. Signing produksi Android & ikon branding final: uat-required.md #11-#12.
