# FASE A-4 — Uji E2E POS Apotik vs demo.ecampus.id — LULUS PENUH — 2026-08-12

Server: `https://demo.ecampus.id/ecampus/Api_eBisnis` (branch `feat/new-ui-rbac-role-user`
s/d `bfa44710`). Akun `demo` (admin), role uji `am`. Data uji di-provisioning via
`apotik_provision_demo` (guarded: admin + token + hanya server tanpa SIRS).

## Gerbang, hak akses, seed (tanpa data)

| Uji | Hasil | Status |
|---|---|---|
| Hak Akses fix `32e7dda7` | ambil role 48 baris ber-`modul` (POS+IS+Apotik+eMedik) | LULUS |
| Seed role `apotik` | 10 kunci `apotik_*` nyala | LULUS |
| Fail-closed tanpa kunci | 6 aksi apotik 403 | LULUS |
| Grant menu+CRUD via API | `ebisnis_role_menu_simpan` +crud → gerbang lolos | LULUS |
| Pemisahan apoteker vs medis | role `am` (emedic) → `emedik_*` nyala, `apotik_*` mati | LULUS |

## Transaksi nyata (data uji: Paracetamol/LASA/bebas, Codein/narkotika)

| # | Skenario | Hasil NYATA | Status |
|---|---|---|---|
| 1 | Terima PBF (ED 2020 & ED 2030) | stok 0→20, 2 batch FEFO (kedaluwarsa + valid) | LULUS |
| 2 | **Jual batch KEDALUWARSA** | `DITOLAK: batch ... kedaluwarsa 2020-01-01 tidak boleh dijual sama sekali` | **LULUS (penahan)** |
| 3 | Jual tanpa pilih batch | ditolak "pilih batch (FEFO)" | LULUS |
| 4 | Jual batch VALID (qty 5) | success, id=5, total=15000, stok 20→15 | LULUS |
| 5 | Idempoten (ulang kode) | `idempoten=true`, id sama, tak menggandakan | LULUS |
| 6 | Narkotika TANPA register | DITAHAN "nama pembeli WAJIB / wajib resep atau dokter" | LULUS |
| 7 | Narkotika register lengkap | success, id=6, ApotikNarkotikaLog tercatat | LULUS |
| 8 | Opname fisik 12 vs sistem 15 | selisih -3 diposting (ADK), stok →12 | LULUS |
| 9 | Retur penjualan +2 | success, stok →14 | LULUS |

**Jejak stok item1 konsisten:** 0 →(terima +20) 20 →(jual -5) 15 →(opname set 12) 12
→(retur +2) 14. Rumus ledger `SUM((qty+qty_bonus)*jenis)` benar end-to-end.

## Bug ditemukan & diperbaiki lewat E2E (nilai nyata UAT)
1. `ebisnis_role_menu_ambil/simpan` hanya MODUL_POS → kunci varian tak bisa di-grant
   (fix `32e7dda7`).
2. `apotik_bayar` gagal jual-sukses: `TransaksiMedis.jenis_transaksi` NOT NULL tak diisi
   (laten — modul RS demo belum pernah dipakai, INSERT TransaksiMedis pertama). Fix
   `bfa44710`: set `TRX_ITEM` + `sumber=APOTIK` + surface error nyata (bukan generik).
3. `ebisnis_role_menu_simpan` kini terima `crud` opsional (grant CRUD granular via API).

## Catatan lingkungan
- InitSirs TIDAK dipanggil pada startup install eCampus akademik → `ConstantValues.apotik*`
  null setelah restart; `apotik_provision_demo` (idempoten) me-set-nya live tiap sesi.
- Data uji ("UJI-PCT"/"UJI-CDN") sengaja ditinggal di demo (berlabel jelas, dipakai UAT
  ulang). Role `am` SUDAH direstore (apotik sisa-nyala=0).

## Kesimpulan
Seluruh perilaku kritis POS Apotik terbukti di server hidup: penahan kedaluwarsa,
FEFO/batch, register obat terkendali, idempotensi, stok/opname/retur, gerbang RBAC
fail-closed, pemisahan apoteker vs tenaga medis. **FASE A-4: LULUS.**
