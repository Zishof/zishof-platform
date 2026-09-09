# Hasil Smoke Test Live AB Chicken — 8 September 2026

## Pembaruan setelah aktivasi administratif

API admin hasil deploy telah dapat dipakai. Katalog mengembalikan 14 jenis usaha, 4 paket, dan 60
unit usaha. Registrasi `REG-2026-000001` berhasil diverifikasi secara administratif dan worker
menyelesaikannya sampai status `READY`. Namun bukti step menunjukkan pembuatan schema ERP/audit,
migrasi, pemasangan audit, dan verifikasi schema seluruhnya `SKIPPED` karena tenant tercatat dalam
mode `LEGACY`. Percobaan membaca toko dihentikan aman oleh `TENANT_SCHEMA_REQUIRED`; tidak ada toko
parsial yang ditulis.

Status ini **belum memenuhi baseline AB Chicken**. Source berikutnya harus dideploy, lalu operator
menjalankan `tenant_admin_promote_tenant_only` sampai `TENANT_ONLY_READY`, `schemaReady=true`, dan
`storeApiReady=true`. Baru setelah itu toko pilot `AB-OUT-001 — Pusat AB Chicken` boleh dibuat dan
UAT transaksi dilanjutkan.

## Keputusan sementara

Deployment API terbaru sudah aktif, tetapi tenant AB Chicken belum diprovision pada database. UAT transaksi end-to-end belum boleh dimulai dan tidak boleh diberi status lulus sampai gerbang tenant serta seed data selesai.

## Lingkungan yang diperiksa

| Komponen | Nilai |
|---|---|
| Waktu pemeriksaan | 8 September 2026, mulai sekitar 00.00 WIB |
| Host kanonik | `abchiken.ebisnis.id` |
| Context path | `/ebisnis` |
| Endpoint API | `/ebisnis/Api_eBisnis` |
| Slug yang disyaratkan | `abchiken` |
| Mode yang disyaratkan | `TENANT_ONLY` |
| Schema data yang disyaratkan | `abchiken` |
| Schema audit yang disyaratkan | `abchiken__audit` |
| Nama tampilan yang disyaratkan | `AB Chicken` |

## Hasil aktual

1. Setelah masa startup, root `https://abchiken.ebisnis.id/ebisnis/` kembali merespons HTTP 200.
2. Login melalui endpoint perangkat `/Api_eBisnis` berhasil menggunakan akun demo yang telah disediakan pemilik sistem. Token tidak dicatat pada dokumen atau log hasil.
3. Aksi `tenant_list` pada host kanonik ditolak secara fail-closed dengan kode `TENANT_NOT_READY` dan pesan bahwa alamat tenant belum selesai dikonfigurasi.
4. Aksi `tenant_list` pada host generik untuk akun demo maupun administrator tidak mengembalikan membership tenant.
5. Pemeriksaan publik ketersediaan username menyatakan `abchiken` masih tersedia dengan pratinjau `abchiken.ebisnis.id`.

Gabungan bukti nomor 3–5 menunjukkan tenant `abchiken` belum dibuat atau direservasi. Ini berbeda dengan kasus tenant sudah ada tetapi schema/audit salah: pada kondisi itu username tidak lagi tersedia dan gerbang host akan melanjutkan pemeriksaan alignment berikutnya.

## Yang sudah terbukti dari deployment

- endpoint bermerek eBisnis aktif;
- autentikasi token perangkat aktif;
- kode pengikatan host terbaru aktif karena subdomain yang belum terdaftar ditolak dengan `TENANT_NOT_READY`;
- host tidak jatuh diam-diam ke schema legacy atau tenant lain.

## Prasyarat sebelum UAT dilanjutkan

1. Provision tenant melalui workflow resmi dengan nama tampilan **AB Chicken** dan slug `abchiken`.
2. Pastikan hasil provisioning tepat `TENANT_ONLY`, `schema_name=abchiken`, `audit_schema_name=abchiken__audit`, status `READY` atau `ACTIVE`, serta versi `v24-abchicken-akun-operasional`.
3. Pastikan tepat satu domain primer aktif `abchiken.ebisnis.id` pada `public.tenant_domain`.
4. Tambahkan membership aktif untuk akun demo yang akan menjalankan UAT beserta role dan entitlement modul yang diperlukan.
5. Jalankan seed database utama dan streaming, kemudian verifikator 31/31.
6. Jalankan `script/abchicken/check_abchiken_live_api.ps1`; hanya hasil `LULUS` yang membuka gerbang UAT layar.

File konfigurasi `C:\opt\.g\.h\xxyxyx.txt` pada mesin UAT hanya menyediakan host/port. Username database dan secret autentikasi tidak tersedia di file tersebut. Seed tidak boleh mencoba password, menulis secret ke repository, atau melewati workflow tenant dengan SQL ad-hoc yang tidak mempunyai owner/membership.

## Status matriks

Kasus AB-01 sampai AB-34 tetap `BELUM DIUJI`. AB-01 mempunyai temuan prasyarat `TENANT_NOT_READY`; kasus lain bergantung pada AB-01 dan belum dieksekusi. Tidak ada klaim lulus parsial yang diubah menjadi lulus 100%.

## Retest setelah aktivasi Data Pendaftar

Pada retest berikutnya, host tetap stabil dan login API berhasil, tetapi binding masih `TENANT_NOT_READY`. Status permohonan `REG-2026-000001` adalah `EMAIL_VERIFICATION_PENDING`, tahap dan langkah berikutnya sama-sama `VERIFY_EMAIL`. Baris aktif pada Data Pendaftar bukan pengganti verifikasi email dan bukan bukti bahwa `tenant_registry`, `tenant_domain`, schema data, schema audit, atau membership sudah selesai dibuat. UAT menunggu pemilik membuka tautan verifikasi email dan worker provisioning menyelesaikan tenant hingga `READY`/`ACTIVE`.

## Retest setelah deployment ulang

Pada 8 September 2026 sekitar 00.25 WIB, root host kanonik merespons HTTP 200 pada tiga pemeriksaan berurutan. Login API kembali berhasil, tetapi `tenant_list` masih menghasilkan `TENANT_NOT_READY`. Pemeriksaan username publik tetap menghasilkan `USERNAME_AVAILABLE` untuk `abchiken`. Dengan demikian deployment ulang tidak mengubah prasyarat database: tenant belum dibuat, bukan tertahan oleh cache atau startup aplikasi.

## Bukti UAT database terisolasi untuk dataset pilot

Sebelum seed diterapkan ke tenant live, paket pilot diuji pada PostgreSQL UAT terisolasi dengan schema khusus. Dataset menghasilkan tepat satu toko aktif berkode `AB-OUT-001` bernama **Pusat AB Chicken**, satu gudang utama, satu gudang operasional toko, 50 menu, 100 bahan baku, 50 BOM aktif dengan total 150 rincian, 80 permintaan outlet, serta masing-masing 80 dokumen PR, PO, BAST, tagihan vendor, pembayaran vendor, produksi, pengiriman, dan klaim. POS menghasilkan 120 faktur dan 360 catatan konsumsi bahan berdasarkan BOM.

Verifikator menghasilkan **31/31 LULUS**. Seed kedua tidak menambah dokumen dan seluruh jumlah tetap sama, sehingga idempotensi paket pilot terbukti. Uji posting integrasi menghasilkan 300 jurnal seimbang dan 780 mutasi stok tanpa duplikasi. Provisioning database streaming menghasilkan 80 bukti pengiriman pada eksekusi pertama dan nol tambahan pada eksekusi kedua. Hasil ini membuktikan kesiapan paket data, tetapi tidak menggantikan UAT live pada host kanonik.

Pembatasan satu toko hanya merupakan baseline pilot. Pemeriksaan runtime dan importer menerima satu atau lebih toko, sehingga setelah pilot disetujui tenant dapat ditambah secara bertahap menuju sekitar 90 outlet. Seluruh outlet tetap berada dalam schema tenant `abchiken` dan dipisahkan melalui identitas toko, gudang, hak akses, serta referensi transaksi; tidak dibuat schema baru untuk setiap outlet.

## Retest pukul 00.55 WIB dan keputusan toko pilot

Pemeriksaan ulang endpoint status publik pada 8 September 2026 pukul 00.55 WIB berhasil dengan HTTP 200, tetapi permohonan `REG-2026-000001` masih berstatus `EMAIL_VERIFICATION_PENDING` dan `nextStep=VERIFY_EMAIL`. Nama teknis, username, dan pratinjau domain tetap `abchiken` / `abchiken.ebisnis.id`. Oleh karena itu, tanda **Aktif** pada Data Pendaftar belum membuka tenant live dan UAT layar tetap menunggu verifikasi email serta penyelesaian worker provisioning.

Dataset UAT live setelah tenant siap akan dimulai hanya dengan satu toko aktif: kode `AB-OUT-001`, nama **Pusat AB Chicken**. Keputusan ini khusus untuk pilot project dan bukan batas kapasitas aplikasi. Target produksi tetap sekitar 90 outlet dalam tenant dan schema yang sama.

## Fasilitas verifikasi manual admin

Untuk pilot yang tidak menunggu pengiriman email, admin platform dapat membuka menu **Data Pendaftar**, memilih **Verifikasi Tenant**, lalu mencentang **Email sudah diverifikasi** pada permohonan yang berstatus `EMAIL_VERIFICATION_PENDING`. Admin wajib menuliskan alasan. Sistem menolak pengguna non-admin, menonaktifkan challenge email lama, mengisi waktu verifikasi, mengaktifkan profil pendaftar, mencatat audit admin, dan meneruskan permohonan melalui aturan review/provisioning yang sama dengan verifikasi email normal. Fasilitas ini tidak menyediakan pembatalan verifikasi dan tidak mengubah langsung tabel tenant.

## Retest setelah deploy promosi TENANT_ONLY dan perbaikan ZK

Deploy terbaru sudah memuat aksi `tenant_admin_promote_tenant_only`, tetapi eksekusi live pertama
gagal sebelum pembuatan schema. Stack trace menunjuk `PendaftaranTenantAdminService.java:609`:
Hibernate lama tidak mempunyai pemetaan untuk JDBC type `1111` yang dikembalikan fungsi PostgreSQL
`pg_advisory_xact_lock`. Karena kegagalan terjadi sebelum DDL dan transaksi di-rollback, status tenant
tetap `LEGACY`, `schemaReady=false`, `storeApiReady=false`, dan daftar toko tetap ditolak aman dengan
`TENANT_SCHEMA_REQUIRED`.

Source diperbaiki agar advisory lock tetap blocking tetapi dieksekusi langsung melalui JDBC tanpa
auto-discovery hasil oleh Hibernate. `PreparedStatement` ditutup eksplisit, sedangkan lock tetap
berlaku sampai transaksi commit/rollback. Pesan `This statement has been closed` pada log merupakan
efek lanjutan saat Hibernate membersihkan statement setelah kegagalan mapping `1111`, bukan akar
masalah terpisah. Source kanonik dan mirror menghasilkan class yang identik. Bersamaan dengan itu, layar ZK
Data Pendaftar ditingkatkan: admin platform dapat memakai tombol toolbar **Verifikasi Tenant** bila
filter menghasilkan tepat satu baris, atau tombol **Atur** pada baris tertentu. Dialog native ZK
menampilkan kode/status/tahap permohonan, checkbox **Email sudah diverifikasi**, waktu verifikasi,
serta alasan administratif wajib. Simpan tetap memanggil service kanonik sehingga audit dan transisi
provisioning tidak dapat dilewati.

Verifikasi lokal setelah perubahan: kompilasi Java 7 kanonik dan mirror lulus, hash class identik,
bytecode memanggil `PreparedStatement.execute` dan tidak lagi memakai Hibernate SQLQuery untuk lock,
ZUL valid sebagai XML, dan `TenantAdminApiContractUat` menghasilkan `LULUS=10 GAGAL=0`. Belum ada WAR
yang dibuat. UAT live menunggu deploy ulang source ini, lalu harus mengulang promosi sampai
`TENANT_ONLY_READY` sebelum membuat toko atau seed transaksi.

## Retest promosi setelah advisory lock diperbaiki

Retest pukul 03.51 WIB membuktikan advisory lock telah melewati titik gagal sebelumnya: tidak ada
lagi JDBC type `1111` atau statement tertutup. Promosi kemudian mencapai penyemaian role tenant dan
berhenti aman pada `TenantRoleSeeder.seed`. PostgreSQL mengembalikan SQLState `42601` karena templat
runtime memakai penanda migrasi `{S}`, sedangkan `TenantSqlExecutor` hanya menerima penanda data
runtime `{t}` dan audit `{a}`. Akibatnya `{S}.role_tenant` terkirim secara literal ke database.

Templat seed role telah diperbaiki menjadi `{t}.role_tenant` pada dua referensi. Regression test
sekarang merender `TenantRoleSeeder.templatSisip()` melalui `TenantSqlExecutor`, memastikan hasilnya
memuat `"tenant_uji".role_tenant`, dan gagal bila karakter placeholder `{` masih tersisa. Kompilasi
Java 7 sumber kanonik/mirror lulus, hash class identik, dan `TenantKonteksSelfTest` berakhir dengan
`OK`. Transaksi live yang gagal ter-rollback: status tetap `LEGACY`, `schemaReady=false`,
`storeApiReady=false`, dan belum ada toko yang ditulis.

Pencegahan ini diberlakukan global melalui `TenantSqlExecutor`: setiap SQL runtime dari modul atau
varian mana pun sekarang menolak `{S}`, `{A}`, dan `{SU}` sebelum query dibuat, dengan petunjuk untuk
memakai `{t}` atau `{a}`. Baseline lintas modul tersedia pada
[`../tenant-inventory-sales/07-baseline-penanda-sql-tenant.md`](../tenant-inventory-sales/07-baseline-penanda-sql-tenant.md).

## Promosi sukses dan blocker pembuatan toko pilot

Retest pukul 04.24 WIB berhasil penuh. Aksi promosi mengembalikan `TENANT_ONLY_READY`, tenant
`abchiken` berstatus `READY`, mode `TENANT_ONLY`, `schemaReady=true`, dan `storeApiReady=true`.
Status provisioning membuktikan schema data, schema audit, seluruh migrasi, pemasangan audit,
penyemaian role, serta verifikasi schema berstatus `SUCCESS`. Ini menutup blocker promosi dan
membuktikan pasangan runtime `{t}` telah aktif.

Daftar toko pada data-plane tenant berhasil dibaca dan masih kosong. Pembuatan idempoten toko
`AB-OUT-001 — Pusat AB Chicken` kemudian berhenti sebelum penulisan karena dua advisory lock pada
`TenantAdminApiDispatcher.buatToko` masih memakai `SQLQuery.uniqueResult()`. PostgreSQL
`pg_advisory_xact_lock` mengembalikan `void` sebagai JDBC type `1111`, yang tidak dapat ditemukan
tipenya oleh dialect Hibernate lama. Transaksi rollback dan pemeriksaan sebelumnya membuktikan tidak
ada toko duplikat atau baris parsial.

Kedua lock pembuatan toko telah dipindahkan ke satu helper JDBC transaksional memakai
`PreparedStatement.execute()`. Source kanonik dan mirror identik, keduanya lulus kompilasi Java 7,
class yang dihasilkan identik, dan bytecode membuktikan pemanggilan `prepareStatement`, `execute`,
serta `close`. Kontrak API juga memeriksa constant-pool class agar pola `SQLQuery` dengan hasil
`void` tidak dapat muncul kembali tanpa menggagalkan UAT. Aturan pencegahan lintas modul dicatat pada
[`../tenant-inventory-sales/08-baseline-advisory-lock-postgresql.md`](../tenant-inventory-sales/08-baseline-advisory-lock-postgresql.md).

Perubahan ini perlu dideploy sebelum pembuatan toko pilot dan seed UAT live dapat dilanjutkan.

## Promosi stabil dan blocker parameter brand opsional

Deployment terakhir mempertahankan tenant `abchiken` pada status `READY`, mode `TENANT_ONLY`,
`schemaReady=true`, dan `storeApiReady=true`. Seluruh langkah provisioning schema data dan audit
tetap `SUCCESS`. Ini membuktikan binding host/subdomain tidak kembali ke tenant shared atau mode
legacy.

Retest pembuatan toko pilot berhasil melewati advisory lock, lalu berhenti pada
`TenantDataPlaneService.mirrorToko`. PostgreSQL mengembalikan SQLState `42804`: kolom `brand_id`
bertipe `BIGINT`, tetapi parameter `null` dari toko yang belum mempunyai brand dideteksi sebagai
`bytea` oleh Hibernate legacy. Transaksi di-rollback dan daftar toko sesudah kegagalan tetap nol,
sehingga tidak ada toko parsial atau duplikat.

Source diperbaiki dengan binding `Hibernate.LONG` pada ketiga penggunaan `brand_id`: UPDATE data,
INSERT data, dan INSERT audit. Regression test tanpa database memaksa jalur UPDATE-lalu-INSERT dan
memastikan tepat tiga binding memakai tipe LONG serta tidak ada binding brand tanpa tipe. Kompilasi
Java 7 sumber kanonik dan mirror lulus; hash class `TenantDataPlaneService`,
`TenantKonteksSelfTest`, dan `TenantAdminApiDispatcher` identik; `TenantKonteksSelfTest` berakhir
dengan `OK`.

Aturan pencegahan lintas modul dicatat pada
[`../tenant-inventory-sales/09-baseline-parameter-null-native-sql.md`](../tenant-inventory-sales/09-baseline-parameter-null-native-sql.md).
Perubahan backend ini harus dideploy sebelum retest idempoten toko `AB-OUT-001 — Pusat AB Chicken`.

## Toko pilot terbentuk dan gap identitas ditemukan sebelum seed

Setelah deployment binding tipe `brand_id`, retest live menghasilkan `STORE_CREATED` untuk satu
toko `Pusat AB Chicken` dengan `storeId=6`. Permintaan kedua memakai idempotency key yang sama dan
menghasilkan `STORE_ALREADY_EXISTS`, `created=false`, serta `storeId` yang sama. API daftar juga
menghasilkan tepat satu toko aktif. Tidak ada kegagalan advisory lock atau SQLState `42804`.

Gate sebelum seed kemudian menemukan bahwa response daftar belum memiliki `kode`. Pemeriksaan
source membuktikan mirror toko hanya menulis nama, brand, alamat, kota, telepon, dan status, padahal
schema tenant maupun audit menyediakan kolom `kode`. Menjalankan seed dalam keadaan ini berisiko
membuat baris kedua karena seed mengenali toko lewat `AB-OUT-001`; oleh sebab itu seed ditahan.

Jalur data diperbaiki secara menyeluruh: signature mirror menerima kode, UPDATE/INSERT data dan
audit menulis kode, backfill serta rekonsiliasi membaca kode shared, API daftar mengembalikan kode,
dan semua pemanggil mengirim `Toko.getKode()`. Untuk baris live yang telanjur mempunyai kode kosong,
replay idempoten memanggil pemeriksa sinkronisasi: perbedaan dipulihkan dan diaudit sekali, sedangkan
replay berikutnya tidak menulis ulang. Kode legacy yang benar-benar kosong diikat eksplisit sebagai
`Hibernate.STRING` sesuai baseline parameter nullable.

Kompilasi Java 7 lima class terdampak pada source kanonik dan mirror lulus dengan hash identik.
Regression test memaksa pemulihan kode pada replay pertama dan memastikan replay kedua menjadi
no-op; `TenantKonteksSelfTest` berakhir `OK` dan kontrak API tetap `13/13 LULUS`. Deployment backend
ini menjadi gate terakhir sebelum replay toko, seed live, dan verifikasi volume 31/31.

## Probe deployment kode toko

Server live merespons normal dan tenant tetap `READY`/`TENANT_ONLY`. Tiga replay idempoten
berurutan semuanya mengembalikan `STORE_ALREADY_EXISTS`, `storeId=6`, serta kode shared
`AB-OUT-001`. Namun tiga pembacaan data-plane tenant masih mengembalikan kode kosong. Karena class
baru seharusnya memulihkan perbedaan tersebut pada replay pertama, bukti ini menunjukkan revisi
source r88246 belum aktif pada instance Tomcat yang melayani host kanonik (source mungkin sudah
di-update, tetapi WAR/class belum dibangun atau context belum direstart). Seed tetap ditahan.

## Retest revisi r88246 dan UAT sumber lokal kanonik

Setelah operator mendeploy revisi r88246, replay `tenant_admin_store_create` mengembalikan
`STORE_ALREADY_EXISTS`, `created=false`, `storeId=6`, dan kode `AB-OUT-001`. Pembacaan
`tenant_admin_store_list` kemudian menghasilkan tepat satu toko aktif bernama **Pusat AB Chicken**
dengan kode yang sama. Ini membuktikan class pemulihan identitas toko sudah aktif dan temuan probe
sebelumnya ditutup. Tenant tetap `READY`, mode `TENANT_ONLY`, `schemaReady=true`, serta pasangan
schema `abchiken`/`abchiken__audit` tidak berubah.

Database sumber lokal `ais` selanjutnya diprovisi memakai katalog migrasi server sampai
`v25-master-sales-medan`. Seed akhir menghasilkan 170 pesanan outlet dan masing-masing 170 PR, PO,
BAST, tagihan, pembayaran, produksi, serta pengiriman; klaim 80, faktur POS 120, dan pemakaian bahan
360. Helper operasi aplikasi memposting 50 dokumen pada masing-masing dari lima proses pembentuk
jurnal. Hasil rekonsiliasi adalah 250 jurnal, 500 baris jurnal, dan 650 mutasi stok. Replay seluruh
250 aksi mengembalikan ID jurnal yang sama. Duplikat idempotency key, jurnal tidak seimbang, serta
saldo stok negatif seluruhnya nol.

Seed kemudian diperluas secara idempoten agar layar tidak kehilangan data setelah batch posting.
Pada tiap proses BAST, tagihan, pembayaran, produksi, dan pengiriman sekarang terdapat 170 dokumen:
50 **Telah Diposting**, 100 **Belum Diposting** yang sah, serta 20 dokumen tahap awal. Verifikator
independen berakhir **31/31 LULUS**, dan eksekusi seed kedua tidak menambah dokumen.

UAT layar live belum dapat dinyatakan lulus. Login subdomain meminta email anggota tenant, sedangkan
akun platform `admin` bukan membership AB Chicken dan ditolak `TENANT_ACCESS_DENIED` sebagaimana
mestinya. Kredensial operator tenant diperlukan untuk menguji daftar, filter, status, posting,
screenshot, serta laporan pada host kanonik. Bukti lokal di atas tidak menggantikan bukti layar live.

## Retest r88273: login tenant lulus, entitlement dan role belum selaras

Setelah r88273 dideploy, API berhasil membuat adapter ZK dan login
`abchicken@gmail.com` berhasil. `tenant_list` hanya mengembalikan tenant id 1 berstatus READY dan
toko pilot tetap tepat satu. Isolasi host tidak jatuh ke tenant lain. Namun `si_ab_summary` serta
`si_ab_integrity` ditolak dengan `TENANT_MODULE_DISABLED`. Daftar modul aktif hanya berisi
`POS_FNB`, `MENU_RESEP`, `BAHAN_BAKU`, dan `MEJA_ORDER`; bundle `RESTORAN_KANTIN` belum membawa
`INVENTORY_SALES`, sedangkan `PRODUKSI` masih berstatus PLANNED pada definisi operasional lama.

Pemeriksaan yang sama menemukan perbedaan role: `tenant_list.role=ADMIN_TENANT`, tetapi
`tenant_context.membership_role=OWNER`. Adapter r88273 menautkan `Tbmuser.pendaftar` ke Pendaftar
owner demi scope data legacy, sehingga resolver menemukan membership owner sebelum membership admin.
Ini dikategorikan sebagai eskalasi hak akses dan UAT transaksi dihentikan sebelum mutasi.

Perbaikan source menambahkan `INVENTORY_SALES` ke bundle `RESTORAN_KANTIN`, menyatakan operasi
produksi/distribusi yang sudah tersedia sebagai built-in, serta menyediakan endpoint admin-only
`tenant_admin_entitlement_reconcile`. Endpoint menghitung modul dari jenis usaha tersimpan, tidak
menerima daftar modul arbitrer, tidak mengaktifkan ulang status DISABLED, idempoten, dikunci
transaksional, dan diaudit. Adapter ZK sekarang menunjuk Pendaftar akun admin sendiri; replay aman
khusus adapter r88273 memperbaiki baris live tanpa mengambil alih username lain.

Kompilasi Java 7 source kanonik dan mirror lulus; tiga class utama menghasilkan hash SHA-256 identik;
`TenantAdminApiContractUat` menghasilkan `LULUS=20 GAGAL=0`; dan `TenantKonteksSelfTest` berakhir
`OK`. Deployment berikutnya diperlukan. Sesudah deploy, UAT wajib menjalankan replay akun,
rekonsiliasi entitlement dua kali, memastikan role kedua endpoint sama-sama ADMIN_TENANT, lalu
mengulang ringkasan/integritas sebelum seed atau posting dilanjutkan.

## Retest r88283: identitas dan entitlement lulus; data live belum ditanam

Sesudah r88283 dideploy, login administrator platform dan login anggota tenant sama-sama berhasil.
Replay akun menghasilkan role `ADMIN_TENANT`, status aktif, serta `zkLoginReady=true` tanpa mereset
password. Rekonsiliasi entitlement pertama menambah `INVENTORY_SALES` dan mempromosikan `PRODUKSI`;
modul aktif menjadi `BAHAN_BAKU`, `INVENTORY_SALES`, `MEJA_ORDER`, `MENU_RESEP`, `POS_FNB`, dan
`PRODUKSI`. Eksekusi kedua menghasilkan `added=0` dan `promoted=0`, sehingga sifat idempoten lulus.

Pemeriksaan melalui host kanonik menghasilkan tepat satu tenant id 1 berkode `TEN-2026-000001`,
status `READY`, mode `TENANT_ONLY`, dan role `ADMIN_TENANT` yang sama pada daftar maupun konteks.
Endpoint `si_ab_summary` dan `si_ab_integrity` sekarang dapat diakses, membuktikan entitlement tidak
lagi memblokir operasi. Namun data live baru berisi satu outlet; produk, bahan baku, BOM, pesanan,
pengadaan, produksi, pengiriman, klaim, jurnal, dan konfigurasi akun operasional masih nol. Karena
itu integritas live belum lulus dan pengujian layar belum dimulai.

Percobaan wrapper database lokal berhenti aman sebelum menulis data karena database yang ditunjuk
`C:\opt\.g\.h` mempunyai schema `abchiken` tetapi tidak mempunyai registry/domain tenant live.
Kondisi ini membuktikan database lokal bukan data-plane runtime host kanonik. Pembagian kredensial
database server pada saat itu dihindari dengan aksi admin-only bernama
`tenant_admin_abchicken_seed_uat`. Nama historis tersebut kemudian diganti menjadi endpoint generik
`tenant_admin_demo_seed_uat` dengan `profile=restaurant_network`; bukti berikut tetap mencatat nama
yang berlaku saat smoke test dilakukan. Targetnya dikunci ke registry tenant tujuan, membutuhkan
konfirmasi/alasan/idempotency key, menolak perintah destruktif, menanam resource utama dan streaming,
serta mencatat audit. Kompilasi Java 6 lulus; regression gate menghasilkan `22/22 LULUS`; parser
resource menghasilkan 51 statement utama dan 6 statement streaming tanpa perintah destruktif.
Deployment endpoint ini menjadi gerbang berikut sebelum integritas dan UAT visual dilanjutkan.

## Retest r88300: dataset dan posting lulus, daftar sumber akun perlu satu deploy

Endpoint generik `tenant_admin_demo_seed_uat` aktif pada host kanonik dan profil
`restaurant_network` berhasil ditanam. Dataset live sekarang memuat satu **Pusat AB Chicken**, satu
gudang pusat, 50 menu, 100 bahan baku, 50 BOM, 170 pesanan outlet, masing-masing 170 PR, PO, BAST,
tagihan, pembayaran, produksi, dan pengiriman, 80 klaim, serta 120 faktur POS. Tidak ada layar data
utama pada kontrak API yang berada di bawah 50 record.

Posting 50 faktur POS selesai 50/50 tanpa kegagalan dan menghasilkan 50 ID jurnal unik. Replay
faktur pertama mengembalikan ID jurnal yang sama. Total menjadi 300 jurnal terposting; endpoint
integritas menghasilkan 19/19 pemeriksaan lulus. Filter `Semua/Telah/Belum` membagi POS menjadi
120/50/70 dan kelima proses posting lain masing-masing 170/50/120. Seluruh penanda
`sudahPosting` cocok dengan filter. Replay seed menggunakan idempotency key yang sama menjalankan
0 statement dan mengembalikan `TENANT_DEMO_UAT_SEED_REPLAYED`.

Satu temuan tersisa ditemukan saat membuka daftar sumber akun. PostgreSQL mengembalikan SQLState
`42601`, `syntax error at or near "label"`, dari alias daftar nilai `p(peran,label)`. Query sudah
diperbaiki menjadi `p(peran,nama_label)` dengan alias keluaran eksplisit. Source kanonik dan mirror
identik, kompilasi target keduanya lulus, dan `TenantAdminApiContractUat` menghasilkan
`LULUS=26 GAGAL=0`. Baseline global baru melarang alias SQL yang berbenturan dengan kata kunci dan
regression guard mencegah pola lama muncul kembali. Deployment perbaikan ini diperlukan sebelum
UAT sumber akun dan UAT visual dapat diteruskan.

## Retest live setelah deploy SVN r88305

Retest API pada host `abchiken.ebisnis.id` membuktikan perbaikan alias pemetaan akun telah aktif.
Daftar sumber akun dapat dibaca tanpa SQLState `42601`; pemetaan `BANK_OPERASIONAL`, `GRNI`, dan
`HUTANG_VENDOR` mengarah ke akun tenant yang relevan. Filter status posting juga konsisten:
POS berisi 120 dokumen (50 telah diposting dan 70 belum), sedangkan BAST, tagihan, pembayaran,
produksi, dan pengiriman masing-masing berisi 170 dokumen (50 telah diposting dan 120 belum).
Ringkasan tenant tetap memenuhi 50 produk jual, 100 bahan baku, 50 BOM, 120 transaksi POS, dan
300 jurnal terposting. Seluruh 19 pemeriksaan integritas API lulus.

UAT visual ZK kemudian menemukan tiga blocker yang tidak terlihat dari hasil API: halaman POS legacy
masih membaca tabel bersama sehingga produk, stok, dan transaksi tampak nol; pilihan toko/satuan kerja
laporan masih dapat memuat unit instalasi lain; serta Laba Rugi ZK untuk Pusat AB Chicken kosong
meskipun jurnal tenant tersedia. Karena itu hasil r88305 belum boleh dinyatakan 100%.

Source setelah r88305 menambahkan jembatan laporan tenant-native yang fail-closed untuk 41 jenis
laporan, membatasi toko ke `{t}.toko`, menyaring katalog di server, dan mengganti daftar satuan kerja
global dengan unit tenant aktif. Seluruh 41 query adapter telah dieksekusi pada schema tenant uji;
tidak ditemukan galat sintaks atau alias. Sebanyak 39 laporan berisi data pada sumber lokal. Dua
laporan beban kosong karena sumber lokal belum mempunyai jurnal POS, sehingga keduanya wajib
dibuktikan kembali terhadap data live setelah deploy.

Kompilasi Java 7 source kanonik dan mirror lulus. Hash enam berkas pasangan identik dan
`TenantAdminApiContractUat` menghasilkan `LULUS=30 GAGAL=0`. UAT visual final tetap menunggu
deployment revisi berikutnya; tidak ada klaim lulus 100% sebelum katalog, filter tenant, laporan
keuangan, scroll/pagination, dan ekspor diuji pada server yang telah diperbarui.

## Kesiapan deploy SVN r88322: Kasir ZK tenant-native

Pemeriksaan ulang pada server yang masih menjalankan r88305 mengonfirmasi blocker visual secara
langsung. Dropdown laporan Laba Rugi masih memuat toko dan satuan kerja instalasi lain, sedangkan
hasil Pusat AB Chicken masih menampilkan pesan belum ada data. Kondisi itu konsisten dengan source
lama yang belum mempunyai adapter laporan dan Kasir ZK tenant-native; hasil API 19/19 saja tidak
cukup untuk menyatakan UAT visual lulus.

Source kumulatif sampai r88322 menutup jalur tersebut. Kasir ZK mengambil kategori, 50 produk,
stok bahan, riwayat, KPI, dan analitik dari schema tenant. Checkout tidak lagi memanggil penulis
legacy `koperasi.*`; server memvalidasi ulang toko, gudang operasional, customer walk-in, produk,
harga, akun, serta BOM aktif, kemudian membentuk faktur `DRAF`, detail, dan pemakaian bahan. Harga
browser tidak dijadikan sumber kebenaran. Advisory lock JDBC dan `idempotency_key` mencegah klik
ganda, sementara polling pesanan daring legacy dimatikan pada konteks tenant agar tidak membocorkan
data schema bersama. Seluruh nama dan SQL layanan bersifat generik, bukan khusus AB Chicken.

UAT tulis dijalankan pada database AIS dengan transaksi luar dan rollback. Hasilnya tepat satu
faktur, satu detail, tiga baris bahan BOM, status `DRAF`, `diposting=false`, dan replay idempoten
mengembalikan faktur yang sama. Jumlah faktur setelah rollback kembali persis ke angka sebelum UAT.
UAT baca menjalankan delapan blok query layar: 4 kategori, 50 produk, ringkasan inventori, 5 riwayat
ringkas, 3 kategori analitik, statistik 14 hari, 7 hari ringkasan, dan 120 transaksi riwayat. Semua
bernilai dan terikat ke schema `abchiken`. Panel harian dibatasi sampai `current_date` agar record
contoh bertanggal mendatang tidak masuk KPI operasional hari ini.

Kompilasi Java 7 source kanonik dan mirror lulus. Ketiga pasangan source identik dan regression
gate menghasilkan `TenantAdminApiContractUat LULUS=32 GAGAL=0` pada keduanya. Tidak ada migrasi
schema baru dan tidak dibuat file WAR. Revisi r88322 siap dibangun dengan Ant serta dideploy hanya
ke Tomcat eBisnis. UAT live final tetap harus mengulang Kasir, Posting Penjualan, jurnal, laporan,
scroll/pagination, PDF, dan Excel setelah revision tersebut aktif.

## Retest live r88339: scope tenant lulus, katalog web salah diklasifikasikan

Login ZK memakai akun UAT berhasil pada host kanonik dan membuka POS web tanpa pilihan toko global.
Layar mengunci konteks pada **Pusat AB Chicken**, menampilkan penanda **Kas tenant aktif**, empat
kategori menu tenant, serta ringkasan tepat 100 bahan baku dengan nilai stok. Hal ini membuktikan
host, membership, toko, dan payload bootstrap tenant telah aktif setelah r88339.

Katalog tetap menampilkan `Produk tidak ditemukan`. Analisis source menemukan query katalog memuat
subquery `aturan_diskon` untuk menghitung harga promo. Adapter browser memeriksa kata
`aturan_diskon` sebelum mengenali pola utama `FROM koperasi.produk a`, sehingga array 50 produk
keliru dipetakan ke array promo kosong. Cabang katalog dipindahkan sebelum cabang promo; pencarian
dan filter kategori tetap diterapkan terhadap payload produk yang divalidasi server. Pemeriksaan
sintaks JavaScript dan guard urutan cabang lulus. Perubahan ini membutuhkan satu deployment Tomcat
eBisnis lagi sebelum transaksi checkout live, posting, jurnal, dan laporan dapat dilanjutkan.
