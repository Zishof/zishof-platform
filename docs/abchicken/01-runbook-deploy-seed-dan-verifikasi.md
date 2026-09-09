# Runbook Deploy dan UAT AB Chicken

## Kapan digunakan

Gunakan runbook ini sesudah kode server terbaru tersedia di mesin build dan sebelum mengambil screenshot atau menyusun manual final. Operator memerlukan hak deploy Java AIS, hak membuat schema tenant, akun PostgreSQL untuk database `ais` dan `streaming_ais`, serta kredensial aplikasi yang mempunyai akses AB Chicken. Password tidak ditulis di repository atau command history; gunakan `PGPASSFILE` berizin ketat atau variabel lingkungan sementara.

## Artefak yang wajib ikut deploy

- `TenantSchemaMigrationsV23.java` — tabel generik proses jaringan restoran dan perluasan master.
- `TenantSchemaMigrationsV24.java` — pemetaan akun operasional.
- `TenantSchemaMigrationsV25.java` — medan master sales yang dibutuhkan formulir tenant.
- `TenantSchemaMigrations.java` — katalog migrasi sampai v25.
- `TenantRbac.java` dan `TenantRoleSeeder.java` — area serta hak operasi.
- `TenantHostResolver.java`, `TenantSchemaLocator.java`, `TenantApiDispatcher.java`, dan `TenantDomain.java` — pengikatan exact-match host, slug, schema, audit, dan pilihan tenant.
- `SalesInventoryApiDispatcher.java` — routing API.
- `RestaurantNetworkOperationsApiHelper.java` — list, status, posting, integritas, dan sumber akun lintas tenant restoran.
- `TenantAdminApiDispatcher.java` dan `TenantDemoSeedService.java` — profil seed live admin-only,
  validasi target, advisory lock, idempotensi, dan audit.
- `/web/sql/restaurant-network-demo/*.sql` — profil resource untuk database utama dan `streaming_ais`.

Pohon `src/main/src` adalah kanonik dan `src/main/java` adalah mirror build lain. Hash file terkait harus sama sebelum deploy. Build server dilakukan oleh operator dengan Ant sesuai prosedur server; runbook ini tidak menghasilkan atau menimpa WAR.

## Langkah deploy server

1. Simpan backup database dan WAR aktif serta catat waktu cutover.
2. Pastikan tidak ada build lain yang sedang memakai direktori staging Ant.
3. Jalankan build/deploy Ant di server sebagaimana prosedur operasional.
4. Restart aplikasi dan periksa log startup. Migrasi tenant harus mencapai versi terkini `v25-master-sales-medan` tanpa error.
5. Pastikan health/login lama tetap berfungsi sebelum membuat tenant AB Chicken.
6. Provision tenant dengan nama tampilan **AB Chicken**, `slug=abchiken`, mode `TENANT_ONLY`, schema `abchiken`, audit `abchiken__audit`, dan status `READY`/`ACTIVE`.
7. Buat satu domain primer aktif `abchiken.ebisnis.id` pada `public.tenant_domain` untuk tenant tersebut dan pastikan context path tetap `/ebisnis`.
8. Pastikan akun demo mempunyai membership aktif hanya pada tenant yang dimaksud atau memilih tenant AB Chicken secara eksplisit. Binding host tidak menggantikan pemeriksaan membership.
9. Pastikan reverse proxy meneruskan header `Host` asli sebagai `abchiken.ebisnis.id`; bila backend menerima hostname internal, gerbang host tidak dapat mengenali subdomain publik.

Rollback dipicu jika startup gagal, migrasi tidak tuntas, tenant lain berubah, respons API AB Chicken mengakses schema bersama, atau tes smoke login/regresi gagal. Pada kondisi tersebut, hentikan UAT, kembalikan WAR sebelumnya, dan pulihkan database hanya berdasarkan backup serta catatan migrasi. Jangan menjatuhkan schema yang sudah berisi data tanpa persetujuan dan verifikasi target eksplisit.

## Seed database utama

Untuk tenant demo live, jalur yang direkomendasikan adalah API admin server agar kredensial
PostgreSQL tidak dibagikan ke operator. Panggil `tenant_admin_demo_seed_uat` dengan
`profile=restaurant_network`, `tenantSlug=abchiken`, frasa `SEED_TENANT_DEMO_UAT`,
`idempotencyKey` unik, dan alasan administratif. Endpoint mengambil schema dari registry,
menolak target yang tidak terisolasi serta SQL destruktif, mengisi database utama dan streaming,
kemudian mencatat audit. Setelah respons `TENANT_DEMO_UAT_SEEDED`, ulangi dengan key yang sama
untuk membuktikan respons `TENANT_DEMO_UAT_SEED_REPLAYED`.

Operasi layar memakai prefix canonical `si_restaurant_*`. Alias `si_ab_*` masih diterima server
untuk transisi build lama, tetapi dokumentasi dan build baru wajib memakai prefix canonical.
Class server tidak boleh memakai nama brand tenant. AB Chicken dipertahankan hanya pada profil data,
aset varian, alamat tenant, serta bukti UAT. Bisnis jaringan restoran berikutnya memakai engine dan
RBAC yang sama; bila dataset contohnya berbeda, tambahkan profil SQL baru tanpa menggandakan class
operasi atau menulis schema tenant secara hard-coded.

Wrapper PowerShell berikut tetap digunakan pada sumber lokal, lingkungan staging, atau saat operator
database memang mempunyai akses langsung:

Contoh PowerShell pada mesin yang mempunyai akses database:

```powershell
$env:ABCHICKEN_DB_USER = '<user-db-main>'
$env:PGPASSFILE = '<path-ke-pgpass-sementara>'
& 'C:\opt\AIS\ais\script\abchicken\seed_abchiken_uat.ps1' -Schema abchiken -Database ais
```

Wrapper hanya menerima `abchiken` atau schema sementara `abchiken_uat_*`, memeriksa keberadaan seluruh tabel proses, lalu menjalankan seed idempoten sesuai schema versi terkini. Untuk schema kanonik `abchiken`, seed juga menjalankan `verify_abchiken_tenant_binding.sql` dan berhenti bila host, slug, mode tenant, schema data, schema audit, versi, atau domain primer belum selaras. File `C:\opt\.g\.h\xxyxyx.txt` dipakai untuk host/port saja; nilai `dinamic_local_database` adalah flag dan tidak boleh dianggap nama database. Nama database utama ditetapkan eksplisit sebagai `ais`.

Untuk database sumber lokal yang sengaja belum mempunyai registry/domain produksi, gunakan
`-LocalSource`. Mode ini hanya diterima bila host database adalah loopback (`localhost`,
`127.0.0.1`, atau `::1`); pemeriksaan volume dan relasi tetap penuh. Jangan gunakan switch ini
pada database server atau saat memvalidasi cutover produksi.

## Provision database file

```powershell
$env:ABCHICKEN_STREAMING_DB_USER = '<user-db-streaming>'
$env:PGPASSFILE = '<path-ke-pgpass-sementara>'
& 'C:\opt\AIS\ais\script\abchicken\provision_abchiken_streaming.ps1' -Schema abchiken -StreamingDatabase streaming_ais
```

Proses ini membuat `abchiken.lampiran_blob` dan 80 bukti SVG UAT yang bernilai. Database utama hanya menyimpan metadata serta `storage_key`; payload fisik berada di `streaming_ais`. Penyimpanan terpisah ini harus ikut backup dan importer.

## Verifikasi data sebelum UI

```powershell
$env:ABCHICKEN_DB_USER = '<user-db-main>'
$env:ABCHICKEN_STREAMING_DB_USER = '<user-db-streaming>'
$env:PGPASSFILE = '<path-ke-pgpass-sementara>'
& 'C:\opt\AIS\ais\script\abchicken\verify_abchiken_uat.ps1' -Schema abchiken -Database ais
```

Skrip keluar nonzero bila satu pemeriksaan gagal. Untuk schema kanonik, pemeriksaan pertama membuktikan exact-match `abchiken.ebisnis.id → slug abchiken → TENANT_ONLY → schema abchiken → abchiken__audit`, versi terkini v25, serta tidak ada schema yang dipakai dua tenant. Simpan seluruh output sebagai bukti data, termasuk jumlah aktual dan label `LULUS`. Baseline setelah batch adalah 50 dokumen **Telah Diposting** dan minimal 100 dokumen **Belum Diposting** pada masing-masing proses BAST, tagihan, pembayaran, produksi, dan pengiriman; total debit harus sama dengan kredit dan idempotency key tidak boleh ganda.

Sesudah verifikasi SQL lulus, jalankan smoke test API kanonik tanpa mencetak token:

```powershell
$env:ABCHICKEN_UAT_USER = '<username-demo>'
$env:ABCHICKEN_UAT_PASSWORD = '<secret-sementara>'
& 'C:\opt\AIS\ais\script\abchicken\check_abchiken_live_api.ps1'
Remove-Item Env:ABCHICKEN_UAT_PASSWORD -ErrorAction SilentlyContinue
```

Hasil wajib tepat satu tenant bernama **AB Chicken** serta status konteks, ringkasan, dan integritas `success`. Respons `TENANT_NOT_READY` berarti domain/tenant belum diprovision; jangan melanjutkan seed layar atau memberi status lulus. Bila pemeriksaan ketersediaan username publik masih menyatakan `abchiken` tersedia, tenant belum dibuat sama sekali dan harus melalui workflow provisioning resmi terlebih dahulu.

## Urutan UAT aplikasi

1. Jalankan `abchicken.exe`; pastikan ProductName **AB Chicken**, logo/latar AB Chicken, dan alamat server bawaan `https://abchiken.ebisnis.id/ebisnis/`.
2. Login dan pilih tenant/toko sesuai peran. Uji bahwa pengguna tanpa hak tidak dapat membuka atau memanggil API AB Chicken.
3. Buka Ringkasan UAT dan cocokkan dengan hasil verifikator SQL.
4. Uji paging 50 baris, pencarian, status, cache-dulu, refresh server, dan halaman terakhir di setiap daftar.
5. Jalankan proses hulu berurutan dan rekam nomor dokumen yang sama pada setiap tahap.
6. Pada pengiriman, buktikan event `DELIVERY`, `ARRIVED`, hasil bongkar muat, kekurangan/rusak, backorder, retur/klaim, dan bukti lampiran.
7. Uji POS dan rekonsiliasi konsumsi tiga bahan untuk menu sampel.
8. Buka Sumber Akun Posting. Periksa akun produk, GRNI, Hutang Vendor, dan Bank Operasional; ubah satu pemetaan dengan akun daun relevan lalu kembalikan atau catat konfigurasi final.
9. Posting minimal satu dokumen per proses terlebih dahulu. Pastikan stok dan jurnal sesuai, lalu ulangi aksi yang sama untuk membuktikan idempotensi—tidak boleh ada jurnal atau mutasi ganda.
10. Setelah sampel lolos, posting batch yang siap. Periksa filter Semua/Telah/Belum, total debit=kredit, dan laporan sampai baris paling bawah.

## Build client Windows

```powershell
Set-Location C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis
C:\opt\flutter\bin\flutter.bat test test\abchicken_contract_test.dart test\sidebar_grup_lipat_test.dart
C:\opt\flutter\bin\flutter.bat build windows --release -t lib\main_abchicken.dart --dart-define=EBISNIS_VARIANT=abchicken
```

Hasil kanonik berada di `build\windows\x64\runner\Release\abchicken.exe`. Pesan Flutter dapat tetap menyebut `ebisnis.exe` karena itu target runner dasar; post-build menyalin binary yang sama ke nama distribusi AB Chicken dan resource Windows harus menunjukkan ProductName **AB Chicken**.

## Bukti keluar yang wajib

- log deploy dan versi migrasi;
- hasil verifikator data utama dan streaming;
- hasil test client/server;
- screenshot setiap gerbang UAT, termasuk halaman terakhir daftar/laporan;
- daftar nomor dokumen sampel beserta jurnal dan mutasi stok;
- daftar temuan, perbaikan, retest, dan status final;
- Word, PDF, serta PPTX yang semuanya menyebut versi build/server dan tanggal bukti yang sama.
