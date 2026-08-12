# FASE A-4 — Uji E2E vs demo.ecampus.id (Tahap 2: transaksi) — 2026-08-12

Server: `https://demo.ecampus.id/ecampus/Api_eBisnis`. Akun: `demo` (admin, role aktif `am`).

## Yang TERBUKTI di server hidup (tanpa perlu grant)

| # | Uji | Hasil NYATA | Status |
|---|---|---|---|
| T0 | Endpoint FASE A+B ter-deploy | `apotik_item_cari, apotik_batch_monitor, apotik_bayar, apotik_terima_barang, apotik_opname_simpan, apotik_retur_simpan` semua balas **HTTP 403** (bukan "Aksi tidak dikenal") → keenam aksi DIKENAL server + gerbang menegakkannya | LULUS |
| T1 | Fail-closed konsisten | Semua aksi apotik 403 utk role tanpa kunci (bukan bocor) | LULUS |

403 (bukan 200 dan bukan "unknown") = kode FASE A+B benar-benar hidup di server dan
gerbang `bolehAksesActionKantin` prefix `apotik_*` bekerja persis desain.

## Yang TERTUNDA (butuh grant `apotik_*` pada role uji)

Transaksi penuh — tebus resep, **jual batch kedaluwarsa HARUS DITOLAK**, register
narkotika wajib, FEFO, retry idempoten, terima-PBF/opname/retur — menuntut satu akun
uji yang role-nya punya `apotik_*` nyala. Grant itu TERBLOKIR:

1. **Jalur API** (`ebisnis_role_menu_simpan`): server demo masih memuat versi LAMA
   (`ebisnis_role_menu_ambil` balas 16 baris MODUL_POS saja, tanpa field `modul`) →
   kunci `apotik_*` di payload difilter diam-diam; enable "sukses" tapi `apotik NYALA(0)`.
   Fix sudah ada di commit AIS **`32e7dda7`** (ambil/simpan mencakup modul varian) —
   tinggal ter-deploy.
2. **Jalur ZK admin UI** (Grup Pengguna / TbmroleAction, yang menulis JSON penuh
   termasuk `apotik_*`): browser pane di lingkungan ini tidak meng-composite (screenshot
   timeout, klik-koordinat terblokir); menu ZK bertingkat tidak dapat didorong dgn andal
   secara buta, dan mis-toggle akan merusak konfigurasi role nyata di server demo bersama
   → sengaja TIDAK ditempuh (risiko > manfaat).

## Unblock (satu langkah, di sisi pemilik)

Rebuild WAR dari branch `feat/new-ui-rbac-role-user` **>= `32e7dda7`** lalu redeploy.
Sesudah itu grant via API jalan, dan seluruh transaksi tahap-2 dieksekusi bersih +
aman dalam satu rangkaian (pola: snapshot role → enable `apotik_*` → uji → restore).

## Catatan
Role `am` yang sempat disentuh saat probe SUDAH direstore ke snapshot semula
(`RESTORE-AM: success`). Tidak ada perubahan permanen tertinggal di server demo.
