# 01 — Peta Layar & Route

Varian apotik memakai shell bersama (`AppShell` desktop / `AppDrawer` mobile).
Tidak ada named-route; navigasi lewat enum `MenuEBisnis` + builder.

| Menu enum | Kunci permission | Class layar | File |
|---|---|---|---|
| `berandaApotik` | — (selalu, isi difilter) | `BerandaApotikScreen` | `screens/apotik/beranda_apotik_screen.dart` |
| `kasirApotik` | `apotik_kasir` ∪ `apotik_resep` | `KasirApotikScreen` | `screens/apotik/kasir_apotik_screen.dart` |
| `persediaanApotik` | `apotik_formularium` ∪ `apotik_batch` ∪ `apotik_pengadaan` ∪ `apotik_stok_opname` ∪ `apotik_retur` | `PersediaanApotikScreen` | `screens/apotik/persediaan_apotik_screen.dart` |
| `laporanApotik` | `apotik_laporan` ∪ `apotik_narkotika` | `LaporanApotikScreen` | `screens/apotik/laporan_apotik_screen.dart` |

Landing setelah login: `AppProductProfile.buatLayarAwal()` → `BerandaApotikScreen`
(dipakai bersama varian eMedik — dibedakan oleh `aksesMenu` server, bukan binary).

## Target route (bertahap, tanpa mengubah class publik)

Layar existing dipertahankan sebagai **route adapter**:

```dart
class KasirApotikScreen extends StatelessWidget {
  @override Widget build(BuildContext c) => const ApotikPosPage();
}
```

Menu target (dokumen §6.1) yang BELUM punya layar: Antrean Resep, Racikan &
Dispensing, Mutasi Stok, Shift & Kas, Perangkat & Sinkronisasi, Etalase Publik.
Menu baru hanya ditambahkan bila API pendukungnya ada (lihat `02-api-action-map.md`).
