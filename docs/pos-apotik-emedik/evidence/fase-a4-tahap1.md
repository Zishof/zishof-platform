# FASE A-4 — Uji E2E vs demo.ecampus.id (Tahap 1: gerbang & seed) — 2026-08-12

Server: `https://demo.ecampus.id/ecampus/Api_eBisnis` (redeploy pemilik, memuat s/d ~`31ebf3f4`).
Akun uji: `demo` (role aktif `am`, `emedic=true`, admin-global legacy `pedagang==null`).

| # | Uji | Hasil NYATA | Status |
|---|---|---|---|
| U1 | Kunci varian di `aksesMenu` (LANGKAH 1.4) | `apotik_kasir=False, apotik_narkotika=False` (eksplisit hadir bernilai false), `emedik_kasir=True, emedik_deposit=True` (seed role emedic), `kasir=True` (kunci lama utuh) | LULUS |
| U2 | Aksi apotik fail-closed utk role tanpa kunci | `apotik_bayar` → HTTP **403** (build lama menjawab "Aksi tidak dikenal" → bukti deploy + gate bekerja) | LULUS |
| U3 | Role POS lama tak berubah (1.6a) | Role `Kantin`: hanya menu POS lamanya yg nyala; tidak satu pun kunci baru | LULUS |
| U4 | Regresi Inventory & Sales | `si_actor_context` → aktor POS ditolak dispatcher (pesan gerbang sama spt sebelum) | LULUS |
| U5 | Seed role varian (1.5) | `ebisnis_role_list` memuat `apotik`, `pemilik_sales_inventory`, `sales_keliling` | LULUS |

**Pemisahan apoteker vs tenaga medis TERBUKTI di data hidup:** role `am` (`emedic=true`)
mendapat `emedik_*` NYALA dan `apotik_*` MATI persis aturan seed — akun medis tidak bisa
memanggil satu pun aksi apotik (U2).

## Temuan (diperbaiki di commit AIS `32e7dda7`, compile hijau)
`ebisnis_role_menu_ambil/simpan` memfilter HANYA `MODUL_POS` → kunci varian tak pernah
bisa dilihat/diatur dari layar Hak Akses Flutter (simpan "sukses" semu, kunci terfilter
diam-diam). Fix: kedua loop mencakup modul POS + IS + Apotik + eMedik; baris ambil
membawa `modul`; default `boleh` ikut `KUNCI_DEFAULT_NONAKTIF` (bukan hardcode true).

## Tahap 2 (menunggu redeploy memuat `32e7dda7`)
Aktifkan `apotik_*` pada role uji via API yg diperbaiki (snapshot→restore), lalu:
tebus resep, JUAL BATCH KEDALUWARSA HARUS DITOLAK, register narkotika wajib,
FEFO sukses, retry idempoten, opname/terima-PBF/retur FASE B.
