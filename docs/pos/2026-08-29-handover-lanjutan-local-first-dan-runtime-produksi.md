# Handover Lanjutan — Local-First CRUD dan Runtime Produksi

Tanggal: 29 Agustus 2026  
Target pembaca: AI/sesi pengembangan berikutnya pada komputer yang sama

## Tujuan

Dokumen ini adalah titik serah-terima kerja terkini. Jangan menganggap seluruh permintaan historis sudah selesai hanya karena pernah dibahas. Verifikasi source, status Git/SVN, hasil pengujian, dan perilaku runtime sebelum mengubah atau merilis apa pun.

Prinsip wajib pekerjaan berikutnya adalah **Local-First untuk seluruh CRUD**: mutasi disimpan ke database lokal terlebih dahulu, UI membaca data lokal, lalu sinkronisasi server berjalan di latar belakang secara idempoten.

## Baca lebih dahulu

1. [Handover utama Local-First, biometrik, dan ePesantren](HANDOVER_AI_LOCAL_FIRST_BIOMETRIK_EPESANTREN_2026-08-29.md)
2. [Indeks dokumentasi POS](README.md)
3. [Fase 9 — Runtime Produksi](2026-08-29-fase-9-runtime-produksi.md)
4. [Blueprint menu terpadu](2026-08-25-audit-redundansi-dan-blueprint-menu-terpadu.md)
5. [Rancangan terpadu pengadaan sampai POS](2026-08-25-rancangan-terpadu-pengadaan-pergudangan-distribusi-produksi-pos.md)

## Lokasi source of truth

| Area | Lokasi |
|---|---|
| Repository Desktop/Android Flutter | `C:\opt\CodeBaseDesktopDanMobile` |
| Aplikasi Flutter eBisnis/POS | `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis` |
| Dokumentasi bersama | `C:\opt\CodeBaseDesktopDanMobile\docs\pos` |
| Backend Java canonical | `C:\opt\AIS\ais\src\main\src` |
| Backend Java mirror | `C:\opt\AIS\ais\src\main\java` |
| Webapp JSP/ZUL/CSS | `C:\opt\AIS\ais\src\main\webapp` |

Backend canonical dan mirror harus identik untuk file yang memang dipelihara pada kedua pohon. Bandingkan isi dan package sebelum menyalin perubahan.

## Sudah dikerjakan dan terverifikasi pada sesi terakhir

### Runtime Produksi Flutter

File:

- `apps/ebisnis/lib/screens/produksi_screen.dart`
- `apps/ebisnis/lib/widgets/app_shell.dart`
- `apps/ebisnis/test/produksi_menu_contract_test.dart`

Hasil:

- Pemanggilan `ApiClient.post(...)` yang tidak tersedia diganti dengan `ApiClient.instance.aksi(...)`.
- Action backend: `produksi_list`, `produksi_detail`, `produksi_status`, dan `produksi_simpan`.
- Menu Produksi dipasang di shell bersama Desktop/Android:

| Hak/menu | Jenis backend |
|---|---|
| `produksi_bill_of_material` | `bill_of_material` |
| `produksi_work_order` | `work_order` |
| `produksi_material_issue` | `material_issue` |
| `produksi_material_return` | `material_return` |
| `produksi_production_output` | `production_output` |
| `produksi_production_waste` | `production_waste` |
| `produksi_production_cost` | `production_cost` |

Verifikasi terakhir:

- `flutter test test\produksi_menu_contract_test.dart`: **3 test lulus**.
- `flutter analyze lib\screens\produksi_screen.dart lib\widgets\app_shell.dart`: **No issues found**.

### Backend Produksi

File:

- `C:\opt\AIS\ais\src\main\src\ais\action\servlet\api\ProduksiApiHelper.java`
- `C:\opt\AIS\ais\src\main\java\ais\action\servlet\api\ProduksiApiHelper.java`
- routing terkait di `PosApi.java`

Hasil:

- Routing action Produksi diarahkan ke `ProduksiApiHelper`.
- `openSession()` ditutup melalui `HibernateUtil.closeSessionQuietly(...)` di `finally`.
- Helper penutupan melakukan rollback transaksi aktif, `clear`, `disconnect`, dan `close` secara aman.
- Hash canonical dan mirror telah diverifikasi sama.
- Kompilasi terarah Java 1.7 dengan `-source 1.7 -target 1.7 -implicit:none` berhasil (`JAVAC_EXIT=0`).
- Output kompilasi berada di `.codex-build/produksi-targeted-20260829`, bukan direktori source.
- Jumlah `.class` di samping `.java` pada pemeriksaan terakhir: **0**.
- Status SVN terarah file backend Produksi bersih pada pemeriksaan terakhir.

### Dokumentasi

- [Fase 9 — Runtime Produksi](2026-08-29-fase-9-runtime-produksi.md) telah dibuat dan ditautkan dari indeks.

## Belum boleh dianggap selesai

Runtime Produksi masih terbukti memakai panggilan API langsung. **Adapter Local-First lengkap untuk CRUD Produksi belum terverifikasi dan belum boleh dianggap selesai.**

Permintaan historis yang luas—Pergudangan, Pengiriman, Pengadaan, Akuntansi, POS, Apotik, data contoh, sinkronisasi lintas kasir, JSP, ZKoss, dan Android—harus diaudit terhadap source aktual dan dokumen fase masing-masing. Percakapan bukan bukti implementasi.

Repository Flutter juga memiliki banyak perubahan sesi lain. Jangan memakai `git reset`, `git clean`, checkout/revert massal, atau menimpa perubahan di luar scope.

## Kontrak wajib Local-First untuk semua CRUD

### Isolasi data

- Setiap build variant memiliki direktori/database lokal sendiri agar eBisnis, Apotik, eMedik, Al-Bahjah, dan varian lain dapat dipasang bersamaan.
- Pisahkan data minimal berdasarkan `variant`, `tenantId`, dan `storeId`.
- Jangan menyimpan transaksi toko lain.
- Backup transaksi kasir lain hanya boleh untuk toko yang sama.

### Create

1. Validasi input di perangkat.
2. Buat ID/mutation ID stabil di client.
3. Simpan master, detail, audit metadata, dan outbox dalam satu transaksi database lokal.
4. UI langsung membaca hasil lokal.
5. Worker mengirim ke server di latar belakang ketika online.
6. Server memakai idempotency key agar retry tidak membuat duplikasi.

### Read

1. Render data lokal lebih dahulu.
2. Refresh server secara asinkron, incremental, dan berpaginasi.
3. Merge hasil server secara idempoten ke local store.
4. Jangan memuat seluruh katalog, pelanggan, atau transaksi besar pada pembukaan halaman; gunakan lazy loading, indeks pencarian, dan paging.

### Update

1. Simpan perubahan dan versi lokal terlebih dahulu.
2. Tambahkan mutasi update ke outbox.
3. Gunakan `version`, `updatedAt`, checksum, atau ETag untuk konflik.
4. Data finansial/stok/jurnal tidak boleh ditimpa diam-diam; konflik harus terlihat dan dapat direkonsiliasi.

### Delete

- Gunakan tombstone/soft delete lokal lebih dahulu.
- Pertahankan tombstone sampai server mengakui.
- Untuk transaksi finansial, stok, pengadaan, produksi, dan pembayaran, gunakan pembatalan atau koreksi kompensasi yang audit-able, bukan hard delete.

### Status sinkronisasi minimum

- `PENDING`: aman di lokal, belum terkirim.
- `SYNCING`: sedang dikirim.
- `SYNCED`: server telah mengakui.
- `FAILED`: gagal sementara dan akan retry.
- `CONFLICT`: perlu rekonsiliasi.
- `TOMBSTONE`: penghapusan lokal menunggu/selesai disinkronkan.

Retry pertama setelah kegagalan: **10 menit**, lalu backoff terbatas. Sinkronisasi tidak boleh memblokir UI atau startup Tomcat/aplikasi.

### Audit metadata minimum

- `mutationId`/idempotency key;
- `variant`, `tenantId`, `storeId`;
- ID/nama perangkat;
- user dan kasir pembuat/pengubah;
- waktu perangkat dan server;
- versi record;
- status sync, jumlah retry, error terakhir;
- checksum payload bila relevan.

### Ketahanan data

- Update aplikasi tidak boleh menghapus database lokal.
- Gunakan lokasi persisten khusus varian, bukan cache.
- Android menghapus app-private storage saat uninstall. Ketahanan setelah uninstall memerlukan backup terenkripsi yang disetujui pengguna, ekspor/restore, server, atau replikasi peer kasir satu toko; jangan menjanjikan hal yang tidak dijamin platform.
- Data sensitif harus terenkripsi dan tidak boleh lintas tenant/toko.

## Definition of Done setiap CRUD

- Berfungsi online dan offline.
- Save lokal terjadi sebelum request jaringan.
- Restart tidak menghilangkan mutasi pending.
- Retry tidak membuat duplikasi.
- Read awal tidak memuat data besar penuh.
- Update/delete mempunyai strategi konflik dan audit.
- Isolasi variant/tenant/toko diuji.
- Replikasi kasir terbatas pada toko yang sama.
- Status sinkronisasi terlihat dan informatif.
- Desktop dan Android diuji bila source bersama.
- Backend tetap Java 1.7/gaya Java 1.6.
- `openSession()`/`currentNativeSession()` ditutup di `finally`; `currentSession()` tidak ditutup manual.
- Tidak ada `.class` di direktori source.
- Perubahan dan UAT dicatat di `docs/pos`.

## Urutan lanjutan

1. Audit semua modul dan buat matriks CRUD: local DB, outbox, worker, konflik, idempotensi, paging, dan test.
2. Temukan komponen Local-First generik yang sudah ada dan perluas; hindari sinkronisasi bespoke per layar.
3. Migrasikan CRUD Produksi dari API langsung ke repository Local-First tanpa memutus kontrak backend.
4. Tambahkan test offline create/update/delete, restart recovery, retry 10 menit, idempotency, konflik, dan replikasi satu toko.
5. Audit parity Desktop/Android serta bypass tampilan admin `Common.apakahAdmin() == true` tanpa melemahkan otorisasi backend.
6. Jalankan UAT dan simpan bukti di dokumentasi.
7. Commit/push/publish hanya bila pengguna meminta secara eksplisit pada sesi itu.

## Perintah awal sesi berikutnya

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile
git status --short
git log -10 --oneline

svn status C:\opt\AIS\ais\src\main\src
svn status C:\opt\AIS\ais\src\main\java

Get-ChildItem C:\opt\AIS\ais\src\main\src -Filter *.class -Recurse
Get-ChildItem C:\opt\AIS\ais\src\main\java -Filter *.class -Recurse

Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
C:\opt\flutter\bin\flutter.bat analyze lib\screens\produksi_screen.dart lib\widgets\app_shell.dart
C:\opt\flutter\bin\flutter.bat test test\produksi_menu_contract_test.dart
```

Kompilasi Java harus memakai `-d` ke direktori terisolasi, misalnya `C:\opt\AIS\ais\src\main\.codex-build\<nama-verifikasi>`. Jangan menghasilkan `.class` di source.

## Perintah/prompt untuk melanjutkan sesi ini

Salin prompt berikut ke sesi AI baru:

```text
Baca seluruh dokumen berikut sampai selesai sebelum mengubah kode:
1. C:\opt\CodeBaseDesktopDanMobile\docs\pos\2026-08-29-handover-lanjutan-local-first-dan-runtime-produksi.md
2. C:\opt\CodeBaseDesktopDanMobile\docs\pos\HANDOVER_AI_LOCAL_FIRST_BIOMETRIK_EPESANTREN_2026-08-29.md
3. C:\opt\CodeBaseDesktopDanMobile\docs\pos\README.md
4. C:\opt\CodeBaseDesktopDanMobile\docs\pos\2026-08-29-fase-9-runtime-produksi.md

Audit source dan status Git/SVN aktual karena sesi AI lain bekerja pada komputer dan repository yang sama. Pertahankan perubahan milik sesi lain; jangan gunakan git reset, git clean, checkout massal, atau revert yang tidak diminta.

Lanjutkan implementasi dengan prinsip wajib Local-First untuk SEMUA CRUD: save lokal dan outbox atomik lebih dahulu, read lokal lebih dahulu dengan lazy refresh, sinkronisasi background idempoten, retry pertama 10 menit setelah gagal, update dengan version/conflict handling, dan delete dengan tombstone atau koreksi kompensasi. Pisahkan storage per build variant, tenant, dan toko; backup lintas kasir hanya untuk toko yang sama. Mulai dengan audit dan migrasi CRUD Produksi yang saat ini masih terbukti memakai API langsung.

Pertahankan backend Java 1.7/gaya Java 1.6. Tutup openSession/currentNativeSession di finally dengan clear/disconnect/close dan jangan tutup currentSession manual. Serahkan perubahan schema kepada Hibernate. Jangan hasilkan .class di direktori source; gunakan output kompilasi terisolasi.

Jalankan test terarah Desktop/Android dan backend, lalu catat perubahan serta UAT di C:\opt\CodeBaseDesktopDanMobile\docs\pos. Jangan commit, push, publish, atau deploy kecuali saya meminta eksplisit pada sesi ini.
```

## Status version control saat handover

Status terarah Flutter terakhir:

```text
M  apps/ebisnis/lib/widgets/app_shell.dart
?? apps/ebisnis/lib/screens/produksi_screen.dart
?? apps/ebisnis/test/produksi_menu_contract_test.dart
M  docs/pos/README.md
?? docs/pos/2026-08-29-fase-9-runtime-produksi.md
```

Daftar ini bukan pengganti pemeriksaan terbaru. Ada perubahan lain dari sesi berbeda. Tidak ada commit, push, release, atau deployment sebagai bagian pembuatan handover ini.
