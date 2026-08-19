# 04 — Matriks Reuse / Refactor / Create

Prinsip: **pakai ulang dulu**, refactor bila perlu, buat baru hanya bila memang belum ada.

## REUSE (jangan duplikasi)

| Komponen existing | Dipakai untuk |
|---|---|
| `AppShell` / `AppDrawer` | shell desktop & mobile — cukup ditambah grup menu apotik |
| `MasterOffline` (`daftarCacheDulu`, `simpanAtauAntre`) | baca lokal-dulu + antrean offline seluruh layar apotik |
| `IndikatorSinkronMaster`, `KilauBaris`, `BannerPerubahanServer` | status sinkron + animasi perubahan |
| `prosesSimpanMaster`, `AuditReasonDialog`-equivalent | alur simpan + alasan |
| `tampilkanRiwayatData` | riwayat AuditTrails per baris |
| `ApiClient`, `Sesi`, `AppProductProfile` | transport, identitas, varian |
| `pos_help.dart` | bantuan kontekstual (disatukan, hindari tombol ganda) |

## REFACTOR

| Sekarang | Menjadi |
|---|---|
| `persediaan_apotik_screen.dart` (1157) | `features/apotik/inventory/` per tab, layar lama jadi adapter |
| `kasir_apotik_screen.dart` (748) | `features/apotik/pos/` (page + katalog + keranjang + sheet) |
| `laporan_apotik_screen.dart` (492) | `features/apotik/reports/` per laporan |
| warna hard-code | `ApotikDesignTokens` (ThemeExtension) |
| cek lebar ad-hoc | `ApotikBreakpoints` |

## CREATE (baru, namespace apotik)

`core/`: `apotik_design_tokens.dart`, `apotik_breakpoints.dart`, `apotik_formatters.dart`
`shared/widgets/`: `apotik_context_bar`, `apotik_page_header`, `apotik_status_pill`,
`apotik_empty_state`, `apotik_error_state`, `apotik_loading_state`,
`medication_card`, `batch_status_badge`, `responsive_master_detail`, `mobile_sticky_action`.

Komponen menjadi **shared global** hanya bila benar-benar generik; sisanya tetap
di namespace apotik agar varian lain tidak terdampak.
