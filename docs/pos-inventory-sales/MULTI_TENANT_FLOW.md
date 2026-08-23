# Aliran penyimpanan lokal Flutter di bawah multi-tenant — keadaan kini dan sasaran

Deliverable **FASE P0 §8.3**.

> **Penyimpangan jalur (disengaja).** MD §8.3 menyuruh menulis ke
> `zishof-platform/docs/inventory-sales/MULTI_TENANT_FLOW.md`. Direktori
> `docs/pos-inventory-sales/` sudah memuat rangkaian dokumen pokok subjek yang
> sama (00-baseline, 01-source-inventory, 01-gap-ledger, 02-decisions, handover
> 12 Agustus 2026, uat/, evidence/). Membuat `docs/inventory-sales/` di
> sebelahnya menghasilkan dua direktori bernama nyaris sama untuk satu
> pekerjaan. Dokumen ini karena itu bergabung ke direktori yang sudah ada.

## 1. Ringkasnya

Aplikasi ini **belum bisa melayani lebih dari satu tenant pada satu pemasangan.**
Pemisahan penyimpanan yang ada memisahkan **varian build**
(ebisnis / albahjah / inventory_sales), bukan pendaftar.

Kabar baiknya: sambungan yang dibutuhkan **sudah ada dan sudah dipakai**.
`CoreDb._storageNamespace` sudah menamai berkas basis data, berkas cadangan
JSONL, dan folder cadangan sekaligus. Yang perlu diubah adalah **isinya**, bukan
membangun mekanisme baru.

## 2. Permukaan penyimpanan dan pemisahannya sekarang

| Permukaan | Kunci pemisah sekarang | Aman lintas tenant? |
|---|---|---|
| Berkas SQLite `ebisnis_<ns>.db` | varian build | **Tidak** |
| 10 tabel di dalamnya | — (satu basis data) | **Tidak** |
| Cadangan JSONL `transaksi-pos-<ns>-backup.jsonl` | varian build | **Tidak** |
| Folder `Dokumen/eBisnis/<ns>/Backup` | varian build | **Tidak** |
| `SharedPreferences`: `token`, `server_host`, `server_https`, `server_context_path` | **tidak ada** | **Tidak** |
| `SharedPreferences`: `auth_luring_hash`, `auth_luring_garam` | **tidak ada** | **Tidak** |
| `Sesi.instance` (singleton memori) | — | **Tidak** |
| `transaksi_pending` | `akun_kunci` + `toko_id` + `id_perangkat` | **Ya (preseden)** |
| `toko_aktif_akun` / `toko_aktif_lokal` | `akun_kunci` per userId | **Ya (preseden)** |

Sepuluh tabel CoreDb: `anggota_cache`, `cache_referensi`, `error_log`,
`id_sementara`, `outbox_is`, `outbox_master`, `produk_cache`, `sesi_kas_lokal`,
`toko_aktif_akun`, `transaksi_pending`.

## 3. Empat pemblokir

### B-1 Namespace terikat waktu kompilasi
`AppVariant.storageNamespace` adalah **`static const`**, dipasang di
`bootstrap.dart:49` dan `main.dart:46`. Nilainya tidak dapat memuat identitas
tenant yang baru diketahui **sesudah** login.

### B-2 Namespace terkunci setelah basis data dibuka
`CoreDb.configureStorage` melempar `StateError` bila namespace berubah sesudah
`_db` terbuka. Berpindah tenant saat aplikasi berjalan **mustahil** hari ini —
perlu menutup basis data dan membukanya kembali, atau memulai ulang aplikasi.

### B-3 Kredensial luring tidak terikat tenant
`auth_luring_hash` dan `auth_luring_garam` (core_auth
`verifikator_sandi_lokal.dart`) berada di `SharedPreferences` **tanpa awalan
apa pun**. Sesudah berpindah tenant, kata sandi tenant sebelumnya **masih lolos
verifikasi luring**. Ini berdampak keamanan, bukan sekadar kerapian data.
`token` dan `server_host` juga global untuk satu pemasangan.

### B-4 Outbox tidak bertanda pemilik — paling berbahaya
`transaksi_pending` sudah membawa `akun_kunci`, `toko_id`, dan `id_perangkat`.
Tetapi **`outbox_master` dan `outbox_is` tidak punya satu pun kolom pemilik**:

```
outbox_master(id, aksi, kunci, payload_json, status, pesan_error, percobaan, dibuat_pada)
outbox_is    (id, aksi, kode_unik, payload_json, status, pesan_error, percobaan, dibuat_pada)
```

Akibatnya: mutasi master yang mengantre milik tenant A dapat **terkirim memakai
token tenant B** saat penyiram latar (tiap 5 menit, `MasterOffline.intervalFlush`)
berjalan sesudah perpindahan. Data tenant A masuk ke tenant B tanpa gejala.

## 4. Keputusan: satu perangkat satu tenant, satu tenant banyak perangkat

Ditetapkan 2026-08-23. **Setiap perangkat terikat pada tepat satu tenant**, dan
**satu tenant boleh memakai banyak perangkat**.

Ini memperkecil pekerjaan secara besar-besaran. Tidak ada perpindahan tenant saat
aplikasi berjalan, sehingga B-2 berubah dari pemblokir menjadi **perilaku yang
memang benar**: `configureStorage` yang menolak perubahan namespace sesudah DB
terbuka justru menjadi penjaganya.

### Yang tetap harus dikerjakan

| | Pekerjaan |
|---|---|
| B-1 | Namespace memuat tenant. **Bukan slug perusahaan** — dokumen master §15.2 melarang nama perusahaan pada nama berkas, dan slug diturunkan dari nama itu. Pola yang diminta: `inventory_sales_<serverHash>_<tenantId>_<userHash>.db` untuk data tenant, dan `app_inventory_sales.db` untuk konfigurasi server/tema/daftar tenant terakhir. Cadangan JSONL mengikuti: `transaksi-pos-inventory_sales-<serverHash>-<tenantId>-backup.jsonl`. |
| B-3 | Awalan `<ns>.` pada kunci prefs, **terutama `auth_luring_hash`/`auth_luring_garam`**. Tetap perlu: perangkat dapat dialihkan ke tenant lain, dan kredensial luring tenant lama tidak boleh ikut. |
| B-4 | **Tidak perlu kolom pemilik pada outbox.** Karena satu perangkat hanya melayani satu tenant, antreannya tidak akan pernah bercampur. Cukup **penjagaan pengikatan**. Skema SQLite tetap di `version: 12` — tanpa migrasi. |

### Penjagaan pengikatan tenant

Satu-satunya jalur bahaya yang tersisa adalah **perangkat dialihkan ke tenant lain**
(pegawai pindah cabang, perangkat dipakai ulang). Penjagaannya:

1. Simpan identitas tenant yang terikat pada perangkat ini.
2. Saat login, bandingkan tenant dari server dengan yang terikat.
3. Bila berbeda dan **antrean masih berisi** → tolak dengan jumlah antrean yang
   tertunda. Membiarkannya berarti mutasi tenant lama terkirim memakai token
   tenant baru.
4. Bila berbeda dan antrean kosong → hapus data lokal (DB, cadangan JSONL, kunci
   `auth_luring_*`), lalu ikat ke tenant baru.

### Banyak perangkat per tenant

`transaksi_pending` sudah membawa `id_perangkat`, dan antrean master sudah membawa
`client_mutation_id` yang didedup server lewat `MutasiIdempotenEBisnisUtil`. Jadi
beberapa perangkat menyiram ke tenant yang sama **sudah** aman dari penggandaan.
Yang perlu diperiksa saat P6/P7 hanyalah bahwa `id_perangkat` benar-benar unik per
pemasangan, bukan per model perangkat.

### Yang gugur karena keputusan ini

Dokumen master §14.3 meminta **tenant switcher UI** dan §15.3 meminta **daur hidup perpindahan
11 langkah** (blokir UI → hentikan worker → tunggu operasi → flush → tutup DB → reset cache →
buka DB baru → validasi penanda → muat cache → mulai worker → aktifkan UI), berikut
`tenantEpoch` supaya callback tenant lama tidak mencemari tenant baru. §25.3 bahkan
mencantumkan tenant switcher sebagai butir Definition of Done.

**Semuanya gugur** bila satu perangkat hanya melayani satu tenant. Yang tersisa dari §15 hanya
pemisahan berkas (§15.2) dan penanganan basis data lama tanpa penanda tenant (§15.4) — yang
justru menjadi penting, sebab perangkat yang dialihkan akan menemui DB lama tanpa penanda.

Butir DoD §25.3 "Tenant switcher tersedia" karena itu **sengaja dikesampingkan** atas keputusan
pengguna, bukan terlewat.

## 5. Yang sudah dibangun (P6/P7 tahap pertama)

| | |
|---|---|
| Skema SQLite | naik ke **v13** — tabel `pengikatan_tenant` |
| Deteksi | `CoreDb.periksaPengikatan` → `belumTerikat` / `cocok` / `beda` |
| Penjagaan | `CoreDb.hitungAntreanTertunda` atas tiga sumber antrean |
| Pelepasan | `CoreDb.lepaskanDanArsipkan` — berkas **diarsipkan, bukan dihapus** |
| Keputusan | `PengikatanTenant.periksa` di `apps/ebisnis/lib/services/` |
| Uji | `packages/core_db/test/pengikatan_tenant_test.dart` |

### Antrean lebih dulu, selalu

Bila perangkat dialihkan ke tenant lain dan **masih ada pekerjaan yang belum terkirim**,
pengalihan **ditolak** — bukan dilanjutkan dengan membuang antreannya. Pekerjaan kasir yang
belum sampai ke server adalah uang yang belum tercatat; pemiliknya harus mengirimkannya lebih
dulu dari akun lama.

Baru ketika antreannya kosong: kredensial luring dibuang, basis data lama diarsipkan dengan
cap waktu, lalu perangkat diikat ke tenant baru.

**Urutannya disengaja.** Kredensial luring dibuang **lebih dulu**. Bila pengarsipan gagal di
tengah jalan, yang tertinggal adalah perangkat tanpa jalan masuk luring — bukan perangkat
yang masih menerima kata sandi tenant lama.

### Basis data lama tidak diadopsi diam-diam

Basis data yang naik dari versi sebelum v13 tidak punya penanda tenant. Tabelnya sengaja
dibiarkan **kosong**, bukan diisi tebakan bahwa isinya milik tenant yang pertama kali login.
Bila basis data tanpa penanda itu masih menyimpan antrean, pengikatan ditahan — persis
seperti kasus tenant berbeda. §15.4 melarang menebak.

### Kredensial luring: dibuang, bukan diberi awalan

MD §15.2 mengarah ke pemberian namespace pada kunci `SharedPreferences`. Untuk
`auth_luring_hash`/`auth_luring_garam` yang dipilih adalah **menghapusnya** lewat
`VerifikatorSandiLokal.hapus()` yang memang sudah ada. Awalan hanya menyembunyikan hash lama
di disk; menghapusnya tidak menyisakan rahasia sama sekali. Karena satu perangkat hanya
melayani satu tenant, tidak ada yang hilang.

## 6. Tersambung ke layar login

`PengikatanTenant.periksaSetelahLogin()` dipanggil di `login_screen.dart`, **sesudah** token
tersimpan tetapi **sebelum** apa pun yang lain.

### Urutannya menentukan, bukan sekadar rapi

```
login → simpan token → PERIKSA PENGIKATAN → simpan sandi luring → mulai outbox → masuk
                              ↓ ditahan
                        hapus token, tampilkan alasan, BERHENTI
```

Pemeriksaan diletakkan **sebelum** `VerifikatorSandiLokal.simpan` dan sebelum penyiram
antrean dinyalakan. Kalau diletakkan sesudahnya, perangkat sudah terlanjur menyimpan bukti
kata sandi pengguna baru padahal ia belum boleh masuk — dan penyiram sudah sempat mengirim
antrean tenant lama memakai token tenant baru.

Ketika ditahan, token yang baru saja disimpan **dihapus kembali**. Pengguna tidak boleh
tertinggal dalam keadaan setengah terautentikasi.

### Lima keadaan, dan hanya dua yang menahan

| Keadaan | Sebab | Lanjut? |
|---|---|---|
| `tanpaTenant` | server menjawab `TENANT_ACCESS_DENIED` — pengguna tidak bernaung pada pendaftar mana pun | **ya**, jalur existing |
| `lanjut` | perangkat sudah terikat tenant yang sama, atau baru diikat | ya |
| `dialihkan` | tenant lain, antrean kosong, data lama diarsipkan | ya, dengan pemberitahuan |
| `tertahanAntrean` | tenant lain, antrean **belum terkirim** | **tidak** |
| `pilihTenant` | punya lebih dari satu tenant | **pemilih muncul** |

**`tanpaTenant` adalah keadaan seluruh pengguna hari ini**, dan itulah sebabnya penyambungan
ini tidak mengubah apa pun bagi mereka.

### Gagal terbuka, dengan sengaja

Bila `tenant_context` mengembalikan kode lain — aksinya belum ada di server lama, tenant
sedang suspended, jaringan putus — hasilnya `tanpaTenant`, bukan galat. Login POS yang
selama ini berjalan **tidak boleh** gagal hanya karena lapisan tenant belum siap di
servernya.

Yang **tidak** gagal terbuka adalah `tertahanAntrean`: itu keputusan berdasarkan data lokal
yang pasti, bukan berdasarkan jawaban server yang bisa tidak sampai.

### Pemilih usaha

Muncul **hanya** bila server menjawab `TENANT_SELECTION_REQUIRED`. Pengguna dengan satu
usaha tidak pernah melihatnya — tenantnya dipilih otomatis oleh server (§7.1 butir 3).

**Tidak dapat ditutup begitu saja.** `barrierDismissible: false` dan `PopScope(canPop: false)`;
satu-satunya jalan keluar adalah tombol **Keluar**, yang membatalkan login dan menghapus
token. Menebak salah satu usaha berarti pengguna bekerja pada perusahaan yang keliru tanpa
pernah tahu — dan tidak ada galat apa pun yang akan memberitahunya, karena datanya benar,
perusahaannya yang salah.

**Usaha yang sedang tidak dapat dipakai tetap ditampilkan**, berikut alasannya, hanya tidak
dapat dipilih:

| Status | Yang dilihat pengguna |
|---|---|
| `ACTIVE` / `READY` | dapat dipilih |
| `SUSPENDED` | "Sedang dihentikan sementara — hubungi admin." |
| `PROVISIONING` | "Sedang disiapkan — coba lagi beberapa saat lagi." |
| lainnya | statusnya ditampilkan apa adanya, supaya dapat dilacak |

Kode dan peran ikut tampil di bawah namanya — dua usaha bernama mirip harus dapat dibedakan.

### Pilihan pengguna bukan kewenangan

Tenant yang dipilih dikirim ulang ke server lewat `tenant_context`, dan **server yang tetap
memvalidasi** keanggotaan, status, serta modulnya. Klien hanya menyebut yang mana.

Dan di sini gagal-terbuka **tidak berlaku**: kalau pilihan eksplisit ditolak server —
suspended, modul mati, bukan miliknya — alasannya dilemparkan ke pengguna, bukan dijatuhkan
diam-diam ke schema existing. Jatuh diam-diam berarti ia bekerja pada data yang sama sekali
bukan yang dipilihnya.

Bedanya dengan login tanpa pilihan: di sana gagal-terbuka memang benar, karena pengguna tidak
pernah meminta tenant apa pun.

### `X-Tenant-Id` dikirim otomatis

`ApiClient` menyimpan `tenantId` di `SharedPreferences` dan menyertakannya sebagai header
pada **setiap** permintaan. Klien tidak pernah mengirim nama schema — hanya id ini (§4.7).
Nilainya ikut terhapus bersama `hapusToken()`.

### Bilah atas menampilkan usaha aktif

Chip bernama usaha muncul di **kiri** chip toko — tenant menaungi toko, jadi urutan bacanya
usaha lalu cabangnya. Tooltipnya menyebut kode tenant.

Muncul **hanya** bila `Sesi.instance.tenantNama` terisi. Pengguna tanpa tenant — yaitu semua
orang hari ini — tidak melihat apa pun berubah.

Nama dan kodenya dibaca dari `Sesi`, bukan dari `SharedPreferences`: satu sumber di memori,
supaya tidak ada layar yang menampilkan nilai basi. `ApiClient` mengisinya saat login dan
memuatnya kembali saat bootstrap.

**Nama schema tidak pernah sampai ke sini** (§4.7) — hanya id, kode, dan nama.

### Keluar akun menutup basis data tenant

`ApiClient.hapusToken(tutupBasisData: true)` kini juga membuang jejak tenant dari
`SharedPreferences` dan dari `Sesi`, lalu menutup `CoreDb`.

**Berkasnya tetap di tempatnya.** Keluar akun bukan pengalihan tenant: antrean yang belum
terkirim harus tetap ada ketika pemiliknya masuk kembali. Yang dilepas hanyalah pegangan di
memori; pembukaan berikutnya terjadi dengan sendirinya pada akses pertama.

**Jalur 401 sengaja TIDAK menutup basis data.** Metode yang sama dipanggil lewat `unawaited`
ketika server menolak token, dan di sana kueri lain bisa sedang berjalan — menutup di
tengahnya membuat operasi yang sah gagal. Data lokalnya pun tidak menjadi lebih aman karena
ditutup: ia tetap di disk, dan yang menjaga pengguna berikutnya adalah pengikatan tenant saat
login.

Tiga jalur keluar yang disengaja meminta penutupan: `kasir_screen`, `konfigurasi_screen`, dan
`layar_kunci_screen`.

## 7. Yang belum
- **`token` dan `server_host` masih global** pada `SharedPreferences`. Keduanya kurang
  berbahaya daripada hash luring — token kedaluwarsa sendiri dan server dipilih sadar oleh
  pengguna — tetapi tetap perlu dibereskan.
- **Nama berkas belum memuat tenant.** Di bawah satu-perangkat-satu-tenant, penanda di dalam
  basis data sudah menutup risikonya; pemisahan berkas per §15.2 baru diperlukan bila kelak
  satu perangkat harus memuat dua tenant sekaligus.

## 8. Yang belum diputuskan

- Nasib data lokal tenant lama saat perangkat dialihkan: dihapus (usulan di atas)
  atau diarsipkan dulu.
