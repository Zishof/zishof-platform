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

## 4. Sasaran

1. **Namespace memuat tenant** — `<varian>_<slug-tenant>`, dipasang **sesudah**
   login mengembalikan tenant, bukan saat bootstrap. Dengan sendirinya ini
   memisahkan berkas DB, cadangan JSONL, dan folder cadangan sekaligus.
2. **Perpindahan tenant menutup basis data**, lalu membukanya kembali pada
   namespace baru; B-2 berubah dari pemblokir menjadi penjaga yang benar.
3. **Kunci prefs diberi awalan** `<ns>.` — termasuk `token` dan terutama
   `auth_luring_*`.
4. **`outbox_master` dan `outbox_is` diberi kolom pemilik**, mengikuti pola
   `transaksi_pending` yang sudah terbukti; penyiram menyaring berdasarkan
   tenant aktif. Butuh kenaikan versi skema (kini `version: 12`).
5. **Antrean wajib kosong sebelum berpindah tenant**, atau perpindahan ditolak
   dengan pesan yang jelas. Membiarkan antrean menyeberang adalah B-4.

## 5. Yang belum diputuskan

- Apakah satu pemasangan memang perlu berpindah tenant saat berjalan, atau satu
  perangkat cukup melayani satu tenant? Bila cukup satu, B-2 dan B-4 selesai
  hanya dengan penjagaan, tanpa perubahan skema.
- Nasib data lokal tenant lama saat berpindah: disimpan atau dihapus.
