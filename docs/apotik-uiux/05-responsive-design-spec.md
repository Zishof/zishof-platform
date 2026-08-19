# 05 — Spesifikasi Responsif

Kelas layout terpusat (`ApotikBreakpoints`) menggantikan pemeriksaan `width >= 900` ad-hoc.

| Kelas | Lebar (logical px) | Perilaku |
|---|---|---|
| `compactMobile` | < 600 | satu kolom, bottom nav, sticky action, sheet full-screen, target sentuh ≥ 44 dp |
| `tablet` | 600–899 | dua area, detail sebagai right drawer |
| `desktopCompact` | 900–1279 | dua area, keranjang panel kanan yang dapat diciutkan, kolom sekunder tabel disembunyikan |
| `desktopStandard` | 1280–1599 | master-detail berdampingan, POS tiga area |
| `desktopWide` | ≥ 1600 | POS tiga area lapang, tabel kolom lengkap |

## POS tiga area (desktop ≥ 1280)

```
┌── ApotikContextBar (tenant · outlet · terminal · peran · shift · sync · printer · scanner) ──┐
│ [konteks & mode]      │ [katalog obat]                     │ [keranjang + pagar bayar]      │
│  OTC/Resep/Racikan    │  kartu obat + pencarian + scan      │  item, qty stepper, batch      │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

Focus mode: sidebar menjadi rail kompak agar katalog + keranjang maksimal.

## Mobile

Bottom navigation maksimal 4 tujuan: **Kasir · Resep · Riwayat · Lainnya**.
Informasi berisiko tinggi (LASA, terkendali, expiry) tampil SEBELUM tombol tindakan.
Tombol berbahaya dipisah dari tombol utama.
