# UAT Runtime — Grup Produk (Harga Terpusat Lintas Toko)

**Tanggal:** 18 Agustus 2026 (sore, Asia/Jakarta)
**Lingkungan:** UAT Tomcat lokal (`CATALINA_BASE C:\opt\Codex-Worspace\.uat-tomcat-inventory`,
port 18080, heap 10 GB) → PostgreSQL lokal `localhost:5432/ais`.
**Build yang diuji:** SVN `^/src` r77580 + `^/web` r77579 (server/ZK/JSP);
kontrak klien Flutter per git `688222b`.
**Jalur uji:** HTTP JSON via **PosApi** — endpoint yang sama persis dengan klien
POS Desktop/Android — dengan login token Bearer sungguhan (aksi `login`), BUKAN mock.

## Hasil: SELURUH 8 LANGKAH LULUS

| # | Langkah | Hasil |
|---|---|---|
| 1 | `login` (user UAT sekali-pakai) + `grup_produk_daftar` awal | ✓ token terbit; `{"data":[],"status":"success"}` |
| 2 | `grup_produk_simpan` create — "Ayam Marinasi UAT", HPP 12.000 / jual 20.000 | ✓ `{"id":4,"diterapkan":0}` (belum beranggota — benar) |
| 3 | Tempel 2 produk dari **2 toko berbeda** ke grup (produk 7422 toko 4: 1.500/3.000; produk 7423 toko 1: 7.000/10.000) | ✓ |
| 4 | `grup_produk_simpan` update — HPP 13.000 / jual 22.000 | ✓ `{"id":4,"diterapkan":2}` |
| 5 | Verifikasi SQL independen | ✓ kedua baris `koperasi.produk` menjadi 13.000/22.000; **baris audit Envers tertulis PER PRODUK** di `new_audit.produk__audit` (revtype=1 memuat harga baru + FK grup; revisi sebelumnya menyimpan harga lama 7.000/10.000) — inilah alasan propagasi per-baris, bukan bulk HQL; `new_audit.grup_produk__audit` berisi 2 baris (create+update) |
| 6 | `grup_produk_hapus` saat masih beranggota | ✓ **DITOLAK**: "Grup masih memiliki 2 produk anggota. Lepaskan dahulu…" (referential guard bekerja) |
| 7 | Lepas anggota (SQL) + pulihkan harga produk uji → `grup_produk_hapus` | ✓ sukses |
| 8 | `grup_produk_daftar` akhir kosong; `logout`; user UAT dinonaktifkan | ✓ |

Uji negatif tambahan (pass sebelumnya, sesi yang sama): panggilan **anonim** ke
`grup_produk_daftar` via `/Data` ditolak rapi oleh lapisan auth servlet
(`{"status":"90","description":"Pengguna tidak boleh akses"}`), tanpa stacktrace.

## Temuan (keduanya BUKAN bug fitur)

1. **Schema drift DB UAT lokal.** `grup_produk_simpan` sempat gagal
   `SQLGrammarException: kolom this_.kebijakan_retur belum ada` — kolom milik
   fitur LAIN yang lebih baru, hilang di DB UAT karena `hibernate.cfg.xml` UAT
   sengaja menonaktifkan `hbm2ddl.auto` ("skema sudah disiapkan"). Diperbaiki
   manual: `ALTER TABLE koperasi.produk ADD COLUMN kebijakan_retur int8` +
   kolom yang sama pada `new_audit.produk__audit`. **Produksi tidak terdampak**
   (`hbm2ddl.auto=update` aktif di cfg SVN) — tetapi kejadian ini
   mengonfirmasi keharusan urutan deploy: **jalankan
   `webapp/sql/migrasi_grup_produk_audit.sql` SEBELUM restart Tomcat produksi**
   (gotcha Envers: hbm2ddl tidak menyinkron kolom baru ke tabel audit entitas
   `@Audited` yang sudah ada).
2. **Kosmetik amplop error.** Penolakan status-91 (mis. hapus grup beranggota)
   lewat PosApi dinormalisasi menjadi amplop "SERVER_ERROR" generik; kolom
   `description` tetap utuh dan itulah yang ditampilkan layar Flutter, jadi
   pesan ke pengguna benar. Perilaku normalisasi PosApi berlaku seragam untuk
   semua helper — tidak diubah pada pass ini.

## Yang TIDAK dicakup pass ini

- Klik-through UI ZK (`grup_produk.zul`) dan JSP (tab "Grup Produk" di
  Manajemen Barang) — lapisan API di bawah keduanya yang barusan dibuktikan;
  ZK memakai `GrupProdukUtil.terapkanHargaKeAnggota` yang sama persis.
- Jalur fail-closed untuk user ber-ROLE non-admin (kunci `grup_produk`
  KUNCI_DEFAULT_NONAKTIF): terverifikasi lewat penolakan anonim + inspeksi
  kode `bolehAksi`/`bolehAksesActionKantin`, belum lewat akun ber-role
  sungguhan.
- Klien Flutter terhadap server live (kontrak nama aksi dikunci oleh
  `test/grup_produk_kontrak_api_test.dart` sejak `688222b`).

## Catatan metode & kebersihan

- User admin UAT sekali-pakai `uat_grup_admin` dibuat langsung di DB memakai
  `ais.common.DesEncrypter` milik aplikasi (passphrase `AIS_UIN` hardcoded di
  source — sudah menjadi sifat sistem, bukan temuan baru pass ini), login
  sungguhan via `PosApi action=login`, dan **dinonaktifkan segera setelah UAT**.
  Jangan dipakai ulang; hapus barisnya bila ditemukan di lingkungan mana pun.
- Grup uji dihapus; harga kedua produk uji dipulihkan ke nilai awal;
  `grup_produk` FK kedua produk dikembalikan NULL. Tidak ada residu data uji
  selain baris audit (memang append-only by design).

---

## ADDENDUM (18 Agu 2026, malam) — Klik-Through UI JSP LULUS; ZK terblokir harness

### Klik-through JSP e-Kantin (browser sungguhan, bukan curl) — LULUS

Login `login.jsp` → `baru?p=kantin&s=barang` → tab **"Grup Produk (Harga
Terpusat)"** tampil (gate admin lolos; tab memang hanya muncul utk pemanggil
berhak):

1. **Tambah Grup** → modal terbuka → isi KLIK-UAT / "Grup Klik-Through UAT" /
   HPP 15.000 / jual 25.000 → **Simpan & Terapkan** → modal menutup, baris
   muncul di tabel: `KLIK-UAT | Grup Klik-Through UAT | 15.000 | 25.000 | 0 |
   Aktif`. ✓
2. **Ubah** → modal terisi ulang PERSIS nilai tersimpan (round-trip data ✓)
   → harga jual diubah 26.000 → simpan → baris ter-refresh `15.000 | 26.000`. ✓
3. **Hapus** (konfirmasi di-accept) → baris hilang, empty-state "Belum ada
   grup produk." tampil benar. ✓

Perbaikan lingkungan yang diperlukan sebelum uji (drift harness, bukan bug
fitur): `nav.jsp` terbaru butuh class `ais.common.CommonMenu` yang belum ada
di `.uat-classes` (harness dibangun 13 Agu; source sudah maju) — seluruh
`.uat-classes` di-refresh dari kompilasi source r77580 (18.290 class,
resource UAT spt hibernate.cfg.xml tidak disentuh), lalu Tomcat di-restart.

### Klik-through ZK — TERBLOKIR HARNESS (bukan bug fitur)

SEMUA halaman ZK di harness UAT ini mengembalikan HTTP 200 dgn body 0 byte —
termasuk halaman lama yang sudah bertahun-tahun ada (`pages/main/index.zul`,
`toko.zul`, bahkan `google.zul` milik layar login). `zkLoader` tidak pernah
tercatat start di catalina log, dan log 13 Agu (saat harness dibangun) sudah
menunjukkan `SEVERE ... One or more listeners failed to start` — ZK memang
tidak pernah berfungsi di harness ini (dibangun utk UAT modul JSP inventory).
Halaman ZK Grup Produk (`grup_produk.zul` + `GrupProdukAction`) terverifikasi
lewat: kompilasi bersih, pola identik AgamaAction/agama.zul yang berjalan di
produksi, dan logika propagasinya (`GrupProdukUtil`) SUDAH terbukti runtime
lewat UAT API + klik-through JSP di atas. Klik-through ZK dituntaskan di
lingkungan yang ZK-nya hidup (server dev/produksi) pasca-deploy.

Kebersihan: grup uji KLIK-UAT dihapus lewat UI; `koperasi.grup_produk` kosong
(diverifikasi SQL); user `uat_grup_admin` dinonaktifkan kembali.

---

## ADDENDUM 2 (18 Agu 2026, malam) — UAT POS Desktop LULUS via Integration Test; Android tinggal jalankan di perangkat

### POS Desktop (Windows) — LULUS

UAT dijalankan sebagai **Flutter integration test** (`integration_test/
grup_produk_crud_test.dart`) pada device `windows`: aplikasi Windows sungguhan
(`ebisnis.exe`) dibangun lalu layar `GrupProdukScreen` ASLI dijalankan dengan
`ApiClient` ASLI (login token Bearer sungguhan) menunjuk UAT Tomcat lokal —
end-to-end Dart widget → HTTP → PosApi → Hibernate → PostgreSQL, tanpa mock.

Siklus yang lulus (6 detik, `All tests passed!`): muat daftar → **Tambah**
(FLT-UAT / "Grup UAT Flutter" / 17.000 / 28.000, dialog menutup, baris muncul)
→ **Ubah** (round-trip nilai terverifikasi: nama terisi ulang persis; harga
jual diganti 29.000 dan tampil di daftar) → **Hapus** (dialog konfirmasi →
baris hilang) → verifikasi akhir langsung ke server (`grup_produk_daftar`)
bahwa grup uji benar-benar tiada.

Cara menjalankan ulang (kredensial via dart-define, pola sama
android_startup_login_test.dart):

    flutter test integration_test/grup_produk_crud_test.dart -d windows \
      --dart-define=POS_TEST_USERNAME=... --dart-define=POS_TEST_PASSWORD=... \
      --dart-define=POS_TEST_HOST=localhost:18080 \
      --dart-define=POS_TEST_CONTEXT=ais --dart-define=POS_TEST_HTTPS=false

### POS Android — test SIAP, eksekusi menunggu perangkat

Test yang SAMA berjalan tanpa perubahan di Android. Emulator di mesin dev
TERBLOKIR kemampuan mesin: image `android-35;google_apis;x86_64` terpasang dan
AVD `uat_grup_pixel` sudah dibuat, tetapi emulator menolak start — "Android
Emulator hypervisor driver is not installed" (pemasangan driver hypervisor =
perubahan sistem, keputusan pemilik mesin). Dua jalur penyelesaian:

1. **Perangkat fisik via USB** (disarankan): `flutter test integration_test/
   grup_produk_crud_test.dart -d <device-id>` dengan dart-define sama, tetapi
   `POS_TEST_HOST` = IP LAN PC dev (perangkat tidak mengenal `localhost` PC).
2. Pasang driver hypervisor (AEHD/WHPX) lalu jalankan AVD yang sudah tersedia
   (`POS_TEST_HOST=10.0.2.2:18080` dari dalam emulator).

Catatan keyakinan: kode Dart yang barusan lulus di Desktop byte-identik untuk
Android (satu codebase, nol kode platform-specific di layar ini); risiko
khusus-Android (minSdk 23, ABI 32/64-bit) sudah diverifikasi terpisah pada
konfigurasi build. Kebersihan: user UAT dinonaktifkan; `koperasi.grup_produk`
kosong.
