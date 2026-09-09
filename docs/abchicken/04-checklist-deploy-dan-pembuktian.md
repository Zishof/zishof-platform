# Checklist Deploy dan Pembuktian UAT AB Chicken

Tanggal baseline: 7 September 2026. Pemilik deploy diisi oleh operator server. Checklist ini menjaga agar status `LULUS` hanya diberikan dari build, database, dan bukti layar yang sama.

Pendaftaran tenant/toko berikutnya dapat dilakukan tanpa formulir publik melalui API admin pada
[`../pendaftaran-tenant/13-backend-admin-api.md`](../pendaftaran-tenant/13-backend-admin-api.md).
Untuk pilot AB Chicken, API toko hanya boleh menghasilkan `AB-OUT-001 — Pusat AB Chicken`; sekitar
90 outlet ditambahkan sesudah pilot dengan kode berbeda di tenant/schema `abchiken` yang sama.

## Pra-deploy — telah diverifikasi lokal

- [x] Source kanonik `src/main/src` dan mirror `src/main/java` untuk tujuh file server terkait identik.
- [x] Kompilasi target delapan file Java, termasuk integration UAT, berhasil.
- [x] Self-test 27 migrasi schema sampai versi terkini v25 berhasil.
- [x] Self-test RBAC memetakan seluruh 94 aksi `si_*`.
- [x] Seed utama dan streaming idempoten pada PostgreSQL UAT terisolasi.
- [x] Verifikator data menghasilkan 31/31 pemeriksaan lulus, termasuk pembuktian tepat satu toko aktif **Pusat AB Chicken** pada dataset pilot.
- [x] Posting integrasi menghasilkan 300 jurnal seimbang dan 780 mutasi tanpa duplikasi atau stok negatif.
- [x] Importer diuji sampai restore dan rekonsiliasi pada target kosong; mode bawaan tetap dry-run.
- [x] Tes penuh Flutter menghasilkan 803/803 tes lulus.
- [x] Build Windows varian `abchicken` berhasil dan identitas executable benar.
- [x] Client AB Chicken dikunci ke HTTPS `abchiken.ebisnis.id/ebisnis`; konfigurasi perangkat lama tidak dapat mengalihkannya ke tenant lain.
- [x] Verifikator database menerima binding kanonik dan terbukti menolak mismatch host/slug/schema/audit.
- [x] Rencana rollback, seed, verifikasi, dan cutover didokumentasikan.

## Deploy server — wajib dikerjakan operator

- [ ] Catat nama deployer, waktu mulai, commit/snapshot source, dan lokasi backup WAR/database.
- [ ] Build dan deploy menggunakan Ant sesuai prosedur server; jangan memakai WAR buatan sesi ini.
- [ ] Smoke test aksi `tenant_admin_catalog`, `tenant_admin_status`, dan gerbang non-admin pada
      `/Api_eBisnis`; token/password tidak boleh masuk bukti atau log UAT.
- [ ] Bila status workflow sudah siap tetapi `storeApiReady=false`, jalankan
      `tenant_admin_promote_tenant_only` dengan alasan audit. Hanya lanjut bila respons
      `TENANT_ONLY_READY`, `schemaReady=true`, dan `storeApiReady=true` pada pemeriksaan berikutnya.
- [ ] Restart service dan pastikan startup tanpa error migrasi.
- [x] Tenant live mencapai `READY`, mode `TENANT_ONLY`, schema data/audit siap, dan migrasi mencapai versi terkini v25.
- [ ] Smoke test login dan fungsi tenant lama untuk mendeteksi regresi lintas tenant.
- [ ] Pastikan exact-match host `abchiken.ebisnis.id`, context `/ebisnis`, tenant `slug=abchiken`, mode `TENANT_ONLY`, schema `abchiken`, dan audit `abchiken__audit` mengarah ke konfigurasi yang sama.
- [ ] Pastikan `public.tenant_domain` memiliki tepat satu domain primer aktif `abchiken.ebisnis.id` untuk tenant tersebut.
- [ ] Pastikan nama tampilan tenant **AB Chicken** dan nama teknis/slug `abchiken`; jangan menukar ejaan brand dengan ejaan subdomain/schema.
- [ ] Bila email verifikasi sengaja dilewati untuk pilot, admin platform membuka **Data Pendaftar → Verifikasi Tenant**, mencentang **Email sudah diverifikasi**, dan mengisi alasan. Pastikan audit `MANUAL_VERIFICATION` serta `EMAIL_VERIFIED` tercatat dan status lanjut ke review/provisioning.

## Temuan UAT live 8 September 2026

- [x] `tenant_admin_catalog` merespons sukses; 14 jenis usaha, 4 paket, dan 60 unit usaha terbaca.
- [x] Verifikasi administratif `REG-2026-000001` berhasil dengan kode `EMAIL_VERIFIED`.
- [x] Worker menyelesaikan job dan menghasilkan registry tenant `abchiken` berstatus `READY`.
- [x] Guard toko menolak penulisan dengan `TENANT_SCHEMA_REQUIRED`; tidak ada toko parsial atau
      data silang yang ditulis.
- [ ] Isolasi belum lulus pada build live saat bukti ini dicatat: step schema, audit, migrasi, dan
      verifikasi schema berstatus `SKIPPED` karena registry terbentuk pada mode `LEGACY`.
- [x] Source perbaikan menambahkan promosi idempoten `tenant_admin_promote_tenant_only`, indikator
      `schemaReady`/`storeApiReady`, penguncian mode per registry sepanjang job, serta guard
      `MARK_READY` untuk tenant non-LEGACY.
- [x] Kompilasi sumber kanonik dan mirror target Java 7 lulus; kontrak admin API
      `TenantAdminApiContractUat LULUS=10 GAGAL=0`.
- [x] Source promosi telah dideploy; tenant mencapai `TENANT_ONLY_READY`, `schemaReady=true`, dan
      `storeApiReady=true`.
- [x] Retest live menemukan kegagalan pemetaan JDBC type `1111` pada advisory lock; lock dipindahkan
      ke JDBC `PreparedStatement.execute`, statement ditutup eksplisit, dan Hibernate tidak lagi
      melakukan auto-discovery tipe hasil fungsi PostgreSQL.
- [x] ZK Data Pendaftar memiliki dialog native untuk flag verifikasi per tenant, alasan wajib,
      tampilan status, dan guard admin platform; kompilasi kanonik/mirror serta XML ZUL lulus.
- [x] Perbaikan advisory lock dan dialog ZK telah dideploy; error JDBC type `1111` tidak berulang.
- [x] Retest advisory lock lulus dan promosi mencapai seed role; ditemukan SQLState `42601` karena
      placeholder migrasi `{S}` dipakai pada SQL runtime `TenantSqlExecutor`.
- [x] Placeholder seed role diubah ke `{t}` pada source kanonik/mirror; regression test memastikan
      schema terkutip benar dan tidak ada `{...}` tersisa sebelum SQL dieksekusi.
- [x] Guard global `TenantSqlExecutor` menolak `{S}`/`{A}`/`{SU}` pada seluruh SQL runtime sebelum
      mencapai PostgreSQL; baseline developer/deployer ditautkan dari dokumentasi tenant utama.
- [x] `TenantRoleSeeder` dan guard placeholder global telah dideploy; promosi selesai sampai `TENANT_ONLY_READY`.

- [x] Revisi r88246 aktif: replay idempoten toko mengembalikan kode `AB-OUT-001`, `storeId=6`, dan
      daftar data-plane memuat tepat satu **Pusat AB Chicken**.

## Provision data demo sumber lokal — selesai

- [x] Schema lokal `abchiken`/`abchiken__audit` dibentuk dari katalog migrasi sampai v25.
- [x] `seed_abchiken_uat.ps1 -LocalSource` menghasilkan 170 record per rantai operasi utama,
      120 faktur POS, dan tetap idempoten pada eksekusi kedua.
- [x] `provision_abchiken_streaming.ps1` menghasilkan 80 bukti fisik pada `streaming_ais`.
- [x] `verify_abchiken_uat.ps1 -LocalSource` berakhir 31/31 lulus.
- [x] Pemetaan GRNI, Hutang Vendor, Bank Operasional, persediaan, pendapatan, dan HPP menunjuk akun daun aktif.
- [x] Helper aplikasi memposting 50 BAST, 50 tagihan, 50 pembayaran, 50 produksi, dan 50 pengiriman;
      hasil 250 jurnal, 500 baris jurnal, dan 650 mutasi stok.
- [x] Setelah batch, masing-masing proses mempunyai 50 record **Telah Diposting** dan 100 record
      **Belum Diposting**; duplikat idempotency, jurnal tidak seimbang, dan saldo stok negatif semuanya nol.

## UAT live berurutan

- [ ] Login anggota tenant, tenant isolation, RBAC, cache-dulu, refresh, pencarian, filter, dan paging lulus.
      Login API anggota tenant, role `ADMIN_TENANT`, dan entitlement sudah lulus pada r88283;
      cache, pencarian, filter, paging, serta bukti visual masih harus diuji setelah seed live.
- [ ] Master pilot satu toko Pusat AB Chicken, satu gudang utama, satu gudang operasional toko, 50 menu, 100 bahan, dan BOM minimal tiga bahan per menu lulus; perluasan sekitar 90 outlet tetap didukung.
- [ ] Pesanan outlet, pemenuhan stok, PR, PO, BAST, tagihan, pembayaran, produksi/packing, dan pengiriman lulus.
- [ ] Status `DELIVERY`, `ARRIVED`, bongkar muat, backorder, retur, klaim, dan lampiran lulus.
- [ ] POS membentuk penjualan dan konsumsi bahan BOM; stok serta HPP dapat direkonsiliasi.
- [ ] Posting sampel dan pengulangan idempoten lulus sebelum posting batch dilakukan.
- [ ] Filter `Semua`, `Telah Diposting`, dan `Belum Diposting` cocok dengan data database.
- [ ] Buku Besar, Neraca Saldo, Laba Rugi, Neraca, Arus Kas, dan laporan operasional tampil penuh sampai baris terakhir.

## Retest live r88300

- [x] Endpoint generik `si_restaurant_*` aktif; alias kompatibilitas `si_ab_*` menghasilkan
      ringkasan yang sama.
- [x] Dataset live berisi 1 outlet pilot, 1 gudang pusat, 50 menu, 100 bahan, 50 BOM, 120 penjualan
      POS, 170 dokumen per proses utama, dan 80 klaim.
- [x] Posting 50 penjualan POS berhasil tanpa kegagalan; replay dokumen pertama mengembalikan ID
      jurnal yang sama.
- [x] Total live menjadi 300 jurnal terposting, termasuk 50 jurnal POS; 19/19 pemeriksaan integritas
      lulus dan tidak ada jurnal tidak seimbang.
- [x] Filter `Semua/Telah/Belum` pada POS menghasilkan 120/50/70; pada BAST, tagihan, pembayaran,
      produksi, dan pengiriman masing-masing 170/50/120. Penanda baris cocok dengan filternya.
- [x] Replay seed dengan idempotency key yang sama menghasilkan `TENANT_DEMO_UAT_SEED_REPLAYED`
      dan menjalankan 0 statement.
- [ ] Daftar sumber akun live tertahan SQLState `42601` karena alias `label`. Source telah memakai
      `nama_label` dan regression guard telah ditambahkan; perlu deploy lalu retest.

## Retest laporan tenant setelah revisi r88305

- [x] API daftar sumber akun tidak lagi menghasilkan SQLState `42601`.
- [x] Seluruh 19 pemeriksaan integritas API lulus dan jumlah jurnal terposting mencapai 300.
- [x] Adapter 41 laporan tenant berhasil dikompilasi dan seluruh query dijalankan pada schema uji.
- [x] Katalog laporan, toko, dan satuan kerja sudah disaring di server pada source kanonik dan mirror.
- [ ] Deploy revisi jembatan laporan tenant-native pada Tomcat eBisnis.
- [ ] Buka katalog ZK dan pastikan hanya kategori/laporan tenant yang tampil.
- [ ] Pastikan dropdown toko hanya berisi `Pusat AB Chicken` dan unit hanya berisi tenant AB Chicken.
- [ ] Jalankan Jurnal, Buku Besar, Neraca Saldo, Laba Rugi, Neraca, dan Arus Kas untuk periode data UAT.
- [ ] Buktikan laporan bernilai, neraca seimbang, serta scroll/pagination sampai baris terakhir.
- [ ] Buktikan PDF/Excel tidak kosong dan tidak memuat data tenant lain.
- [ ] Retest POS legacy ZK; bila masih nol, lanjutkan adapter produk, stok, dan transaksi POS tenant-native.

## Gerbang deploy Kasir ZK tenant-native r88322

- [x] Kategori dan katalog Kasir dibaca dari schema tenant; uji lokal menampilkan 4 kategori dan 50 produk.
- [x] Riwayat tenant berisi 120 transaksi dan tidak memakai tabel transaksi legacy.
- [x] KPI inventori, mini-riwayat, analitik kategori, statistik 14 hari, dan ringkasan 7 hari bernilai.
- [x] Checkout memvalidasi harga, HPP, akun, gudang, customer, dan BOM di server.
- [x] UAT rollback menghasilkan 1 faktur DRAF, 1 detail, 3 pemakaian bahan, dan replay idempoten.
- [x] Advisory lock memakai JDBC `PreparedStatement.execute()`; hasil fungsi PostgreSQL bertipe void
      tidak dibaca sebagai ResultSet/`uniqueResult`.
- [x] Source kanonik dan mirror identik; kompilasi Java 7 serta kontrak `32/32` lulus.
- [x] Tidak ada migrasi schema dan tidak ada WAR yang dibuat.
- [ ] Build Ant revision r88322 dan deploy hanya ke Tomcat eBisnis.
- [ ] Sesudah deploy, pastikan header pengguna menampilkan revision baru sebelum menguji.
- [ ] Kasir ZK menampilkan 50 produk, transaksi baru masuk sebagai DRAF, dan daftar Posting Penjualan
      bertambah tepat satu tanpa duplikasi.
- [ ] Posting transaksi baru lalu telusuri jurnal Kas/Pendapatan serta HPP/Persediaan sampai Buku Besar.
- [ ] Pastikan dropdown laporan hanya memuat Pusat AB Chicken dan unit tenant, tanpa toko/satker lain.
- [ ] Pastikan Laba Rugi, Neraca Saldo, Neraca, Arus Kas, PDF, dan Excel berisi data live.

## Bukti dan keputusan rilis

- [ ] Screenshot menggunakan area aplikasi penuh, data bernilai, serta judul profesional tanpa hitungan kata.
- [ ] Setiap narasi khusus terhadap layar dan tidak disalin ke layar lain.
- [ ] Diagram tidak memiliki panah yang bertumpuk dengan teks atau kotak.
- [ ] Nomor dokumen dapat ditelusuri dari sumber, mutasi stok, jurnal, Buku Besar, sampai laporan.
- [ ] Daftar temuan, perbaikan, retest, dan hasil aktual dilampirkan.
- [ ] Word, PDF, dan PPTX memakai versi server/client serta tanggal bukti yang sama.
- [ ] Status akhir hanya diubah menjadi `LULUS 100%` bila semua kotak UAT live dan bukti telah terpenuhi.

## Pemicu rollback

Rollback segera bila startup/migrasi gagal, schema tenant lain berubah, API AB Chicken membaca tenant yang salah, posting tidak seimbang atau ganda, stok menjadi negatif, login lama regresi, atau alur kritis pesanan–pengiriman–POS–akuntansi gagal. Hentikan seed/UAT, simpan log dan nomor referensi terakhir, kembalikan artefak aplikasi sebelumnya, lalu pulihkan database hanya dari backup yang sudah diverifikasi. Jangan menghapus schema atau menimpa target importer untuk mengulang proses.

## Batas pilot dan kesiapan ekspansi

Ketentuan tepat satu toko hanya berlaku untuk dataset dan pembuktian fase pilot. Toko tersebut wajib memakai kode `AB-OUT-001` dan nama **Pusat AB Chicken**. Kontrak API, relasi gudang–toko, dokumen pesanan, pengiriman, POS, posting akuntansi, serta importer tetap bersifat multi-outlet. Pemeriksaan integritas runtime dan importer mensyaratkan minimal satu toko, bukan maksimal satu toko, sehingga tenant yang sama dapat dikembangkan secara bertahap menuju sekitar 90 outlet tanpa mengubah model data atau membuat schema baru per outlet. Setiap outlet tambahan tetap berada di schema tenant `abchiken`; pemisahan operasional dilakukan dengan ID toko, gudang, hak akses, dan referensi dokumen.
