# FASE A-4 — Uji E2E vs demo.ecampus.id (Tahap 2 FINAL) — 2026-08-12

Server: `https://demo.ecampus.id/ecampus/Api_eBisnis` (redeploy memuat `32e7dda7`,
terverifikasi: `ebisnis_role_menu_ambil` balas 48 baris + field `modul`).
Akun: `demo` (admin, role aktif `am`).

## LULUS di server hidup

| # | Uji | Hasil NYATA | Status |
|---|---|---|---|
| P1 | Hak Akses fix (`32e7dda7`) ter-deploy | ambil role = 48 baris ber-`modul` (POS+IS+Apotik+eMedik) | LULUS |
| P2 | Seed role `apotik` (LANGKAH 1.5) | 10 kunci `apotik_*` NYALA di role `apotik` | LULUS |
| P3 | Grant menu via API lalu gerbang lolos | set `apotik_*` di role `am` → `apotik_item_cari` = **success** (sebelumnya 403) | LULUS |
| P4 | Fail-closed sebelum grant | keenam aksi apotik 403 tanpa kunci (tahap-1) | LULUS |
| P5 | Validasi handler baca | `resep_detail` id-salah→"Resep tidak ditemukan"; tanpa id→"resep_id wajib"; `item_batch` tanpa id→"item_id wajib", id-salah→"Item tidak ditemukan" | LULUS |
| P6 | CRUD-granular menegakkan (terpisah dari visibilitas menu) | `terima_barang`/`opname_simpan`/`retur_simpan`/`profil_simpan` → "tidak berhak" saat CRUD role belum di-grant (role seed `apotik` punya CRUD; `am` tidak) | LULUS |
| P7 | Fail-closed konstanta SIRS | `apotik_bayar` → "Kode transaksi 'apotik jual' belum terinisialisasi" — guard `ConstantValues.apotikJual == null` bekerja (menolak, tidak mencatat penjualan tak-berkurang-stok) | LULUS |

## TIDAK dapat diuji di server INI (batas lingkungan, bukan cacat kode)

Demo ini **eCampus akademik tanpa modul SIRS ter-provisioning**:
- `apotik_item_cari` (keyword kosong) = **0 item**; `apotik_batch_monitor` = 0 batch;
  `apotik_resep_list` = 0 resep → `sirs.item_medis`/`kadaluarsa`/`resep` kosong.
- `ConstantValues.apotikJual`/`beliMasuk`/`adjustment*`/`apotikRetur` = **null**
  (baris `sirs.kode_transaksi_medis` belum di-seed) → seluruh aksi TULIS apotik
  fail-closed dengan benar.

Akibatnya jalur-positif — penjualan sukses, **JUAL BATCH KEDALUWARSA DITOLAK dgn batch
nyata**, FEFO, register narkotika, retry idempoten, terima-PBF/opname/retur berhasil —
tidak bisa dijalankan di sini. Ketiadaan data + konstanta null adalah tembok lingkungan;
kode jalur-positifnya sudah ter-deploy (terbukti keenam endpoint dikenal + guard di
dalamnya menyala), tinggal butuh server ber-SIRS.

## Yang diperlukan untuk menuntaskan jalur-positif (di sisi pemilik)
Server/tenant dengan **modul SIRS ter-setup**: seed `sirs.kode_transaksi_medis`
(agar `ConstantValues.apotik*` terisi saat init) + minimal 1 `ItemMedis` dgn 2 batch
`Kadaluarsa` (satu ED lampau, satu ED depan) + 1 `Resep`. Di server itu saya jalankan
rangkaian positif lengkap termasuk pembuktian penolakan batch kedaluwarsa.

## Kebersihan
Role `am` yang dipakai probe SUDAH direstore penuh dari snapshot 48-baris
(`RESTORE-AM=success`, `apotik_* sisa-nyala=0`). Tidak ada perubahan tertinggal di demo.
