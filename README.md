# Zishof Platform — Codebase Desktop dan Mobile

Satu basis kode Flutter untuk seluruh lini produk Zishof (eBisnis, eCampus, eSchool,
ePesantren, eKlinik, eMedic, eFarmasi, eLogistik, eMarketPlace), dibangun di atas
**Platform Core** — paket-paket bersama (`packages/core_*`) yang dipakai ulang oleh
tiap aplikasi produk (`apps/*`). Setiap aplikasi produk di-build menjadi installer
terpisah (mis. `eBisnis.exe`/`eBisnis.apk`), walau berbagi satu basis kode.

Server backend tetap Java (lihat `C:\opt\AIS\ais\src\main`) — bertindak sebagai API
murni untuk klien Flutter ini, sekaligus mesin render ZKoss/JSP untuk pengguna yang
belum berpindah dari aplikasi lama (kebijakan transisi bertahap, lihat dokumen
analisis gap POS→Flutter).

## Struktur

```
packages/
  core_sync/     - sinkronisasi lokal<->server, mode semi-offline (baca+tulis tanpa internet)
  core_auth/      - login token/QR (Kasir, Owner, Manajemen)
  core_db/        - SQLite lokal (sqflite/drift), skema per-modul
  core_device/    - identitas mesin, aktivasi QR/kode-install
  core_update/    - auto-update installer
  core_billing/   - integrasi Smartlink, lisensi per mesin, diskon tier
  core_notif/     - notifikasi lokal + push
  core_ui/        - komponen UI bersama, tema
  core_hw/        - printer struk ESC/POS, scanner kamera/infrared

apps/
  ebisnis/        - POS + Owner + Manajemen (produk pertama yang dibangun)
  (produk lain menyusul: ecampus, eschool, epesantren, eklinik, emedic, efarmasi,
   elogistik, emarketplace)
```

## Versioning

Version control ganda: **GitHub** (`github.com/Zishof/zishof-platform`) sebagai
sumber utama, **SVN** (`svn://38.47.178.34/pos/CodeBaseDesktopDanMobile`) sebagai
backup.
