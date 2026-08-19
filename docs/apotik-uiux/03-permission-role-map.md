# 03 — Peta Permission & Peran

Sumber tunggal: `Tbmrole.ebisnisMenu` (JSON) → `EbisnisMenuKatalog` →
aksi `konfigurasi` mengirim `aksesMenu` → `Sesi.bolehMenuVarianBaru(kunci)`.
**Fail-closed**: seluruh kunci apotik ada di `KUNCI_DEFAULT_NONAKTIF`, jadi
kunci yang hilang = menu disembunyikan.

| Kunci | Menu/aksi yang dijaga | Gerbang server (`PosApi.bolehAksesActionKantin`) |
|---|---|---|
| `apotik_kasir` | Kasir Apotek | `apotik_item_*`, `apotik_resep_*` (bersama) |
| `apotik_resep` | Antrean/telaah resep | `apotik_resep_*` |
| `apotik_racikan` | Racikan & dispensing | (belum ada aksi) |
| `apotik_formularium` | Master obat | `apotik_item_profil_simpan`, `apotik_item_*` |
| `apotik_batch` | Batch & expiry | `apotik_item_*` |
| `apotik_pengadaan` | Penerimaan PBF | `apotik_terima_*` |
| `apotik_stok_opname` | Stok opname | `apotik_opname_*` |
| `apotik_retur` | Retur | `apotik_retur_*` |
| `apotik_narkotika` | Register terkendali | laporan terkendali |
| `apotik_laporan` | Laporan | `apotik_laporan_*` |

Admin resmi (`Common.getApakahAdminLain`) lolos seluruh gerbang; `Sesi.isAdmin`
dipakai klien hanya untuk MENAMPILKAN, tidak pernah sebagai izin final.

## Aturan UI

- Menu hanya dirakit bila kuncinya menyala (bukan dirakit lalu di-disable).
- `Ctrl+K` command palette hanya menampilkan tujuan yang sudah lolos izin —
  bukan jalan pintas melewati permission.
- Tindakan sensitif (override harga, batal, void, pilih batch non-FEFO)
  memakai `AuditReasonDialog`; alasan dikirim ke server, bukan sekadar dicatat lokal.
