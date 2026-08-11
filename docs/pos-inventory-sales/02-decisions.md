# Architecture Decision Log — varian inventory_sales

Format: setiap keputusan diberi label sesuai klasifikasi kebenaran PERINTAH_MASTER §0.3.

## D-01 — Kerja langsung di branch existing, bukan branch fitur terpisah
**Status:** diputuskan (DESIGN_DECISION, deviasi sadar dari saran §23 PERINTAH_MASTER)
**Konteks:** §23 menyarankan branch `feat/flutter-pos-inventory-sales-48-screen` (Flutter) dan
`feat/java-api-pos-inventory-sales-trip` (AIS). Kondisi lokal nyata:
1. Kedua working tree DIPAKAI BERSAMA oleh sesi agent lain yang berjalan paralel
   (terbukti: `PenjadwalanUtil.java` sedang dimodifikasi pihak lain saat audit; riwayat sesi
   mencatat commit pihak lain mendarat di branch yang sama sepanjang hari).
2. Working tree AIS di-mirror otomatis near-real-time ke SVN produksi
   (svn://…/ais) — isolasi branch git TIDAK mengisolasi mirror; berpindah branch justru
   mengubah isi mirror produksi secara tak terduga.
3. Seluruh pekerjaan multiplatform sebelumnya di lingkungan ini dikirim per-slice ke
   branch `feat/new-ui-rbac-role-user` (AIS) dan `main` (zishof-platform).
**Keputusan:** commit per vertical slice, scoped per-file, langsung di branch existing.
Perubahan harus SELALU additive/backward-compatible sehingga aman ter-mirror kapan pun.
**Konsekuensi:** tidak ada PR gate; kompensasinya: baseline build sebelum & sesudah tiap
slice + evidence per layar + larangan `git add -A`.

## D-02 — Artefak & evidence disimpan di repo zishof-platform
**Status:** diputuskan (DESIGN_DECISION)
`docs/pos-inventory-sales/` + `docs/input/` hidup di C:\opt\CodeBaseDesktopDanMobile (repo
zishof-platform) sesuai README paket ("salin ke root workspace Flutter atau docs/input").
Repo AIS tidak menerima folder docs baru — commit AIS berisi kode server saja, dengan pesan
commit yang mereferensikan ID requirement (FND-xxx/SCR-xx/TRIP-xxx).

## D-03 — Ekstensi API lewat hook `prosesAksiTambahan` di PosApi
**Status:** diputuskan (DESIGN_DECISION, mengikuti §3.4 PERINTAH_MASTER)
Satu method protected di PosApi yang return false secara default, dipanggil tepat sebelum
fallback "aksi tidak dikenal"; `ApiEBisnis` meng-override dan mendelegasikan ke
`SalesInventoryApiDispatcher`/`SalesInventoryHelper` (class baru, package
`ais.action.servlet.api`). Nol perubahan perilaku untuk seluruh aksi existing; klien lama
tidak terdampak karena hook hanya menangkap action ber-prefix `si_` yang sebelumnya pasti
jatuh ke "aksi tidak dikenal".

## D-04 — Kompatibilitas bahasa Java
**Status:** diputuskan (FACT_SOURCE + kebijakan §2)
Larangan keras §2: tanpa lambda/stream/Optional/record/var/switch-expression. Kode baru
mengikuti gaya file existing (KantinHelper: JSONObject/JSONArray manual, PreparedStatement,
try/finally session). BigDecimal untuk uang di entity/perhitungan baru (bukan double).

## D-05 — Reuse maksimal entity existing (tidak ada duplikasi ledger)
**Status:** diputuskan (DESIGN_DECISION, audit detail menyusul per fase)
- Supplier procurement: `PengadaanFaktur` + `kulakan_faktur_*` (sudah live) = basis layar 20.
- Customer: `AnggotaKoperasi` + profil extension baru bila field sales (termin/limit/area/
  sales owner) tidak ada — TIDAK menambah kolom sembarangan ke entity existing (ERD §1.2).
- Master/transaksi baru (SalesInventory, SPJ, NotaSalesSession, dst.) = entity baru schema
  `koperasi`, `@Audited`, kolom `@Column` eksplisit (landmine implicit-naming Hibernate:
  camelCase TIDAK di-underscore di deployment ini — wajib nama kolom eksplisit di SEMUA
  getter multi-kata).
- Getter terkomputasi di entity WAJIB `@Transient` + setter no-op (landmine terbukti 2×
  menyebabkan Tomcat startup loop di deployment ini).

## D-06 — Baseline diverifikasi sebelum coding
**Status:** selesai (FACT_SOURCE, 2026-08-11)
- AIS: `mvn -o compile` dari `C:\opt\AIS\ais` (root pom) → EXIT=0. Catatan: pom TIDAK berada
  di `src/main` (perintah build harus dijalankan dari root repo checkout).
- Flutter: `flutter analyze` → 31 issue semuanya info/warning (0 error); `flutter test` →
  1 test lulus (hanya smoke test `widget_test.dart`; cakupan test existing minim = fakta
  baseline, ekspansi test masuk DoD per layar).

## D-07 — Sumber kebenaran spesifikasi per layar
**Status:** diputuskan (FACT_MANUAL)
Urutan otoritas saat konflik: (1) Matriks-Paritas-Komponen-48-Layar-v2.csv (komponen wajib
per layar), (2) Panduan-Transisi v2 (konteks operasional + struktur DBF legacy),
(3) MAPPING csv (reuse/aksi API), (4) PERINTAH_MASTER (arsitektur), (5) ERD (data model).
Video sumber tidak tersedia lokal → perilaku runtime murni = UAT_REQUIRED.
