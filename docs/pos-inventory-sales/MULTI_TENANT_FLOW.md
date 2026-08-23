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
| B-1 | Namespace memuat tenant: `<varian>_<slug-tenant>`, dipasang sesudah login. Tetap perlu — dua tenant pada satu mesin (mis. perangkat contoh atau uji) akan berbagi berkas DB tanpa ini. |
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

## 5. Yang belum diputuskan

- Nasib data lokal tenant lama saat perangkat dialihkan: dihapus (usulan di atas)
  atau diarsipkan dulu.
