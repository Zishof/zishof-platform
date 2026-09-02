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

## Skala teks aksesibilitas (ditambahkan Fase 8)

Lebar layar bukan satu-satunya sumbu yang bisa merusak tata letak; **skala
teks** melakukan hal yang sama tanpa mengubah ukuran jendela. Pengujian pada
1,0/1,3/2,0× menemukan enam luberan nyata yang kini diperbaiki:

| Tempat | Sebab | Perbaikan |
|---|---|---|
| `ApotikStatusPill` | `Text` berukuran intrinsik di dalam `Row` | `Flexible` — label membungkus, tidak dipotong (label keselamatan tidak boleh terpenggal diam-diam) |
| Judul panel keranjang | `Text` + `Spacer` | `Expanded` + elipsis |
| Baris harga × qty | `Text` + `Spacer` | `Expanded` + elipsis |
| Total keranjang | nominal lebih lebar dari panel | `Wrap` `spaceBetween` — nominal turun ke baris sendiri, angka uang tidak pernah dipotong |
| Kepala lembar pembayaran | sama seperti di atas | `Wrap` `spaceBetween` |
| "Identitas pembeli" + ikon gembok | `Row` tanpa fleksibilitas | `Flexible` |

Aturan yang berlaku sejak sekarang: **angka uang tidak boleh dielipsis**;
kalau tidak muat, ia pindah baris.
