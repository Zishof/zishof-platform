# 07 — Rencana Implementasi

Mengikuti §20 dokumen perintah. **Tanpa big-bang rewrite**: class & menu publik
existing dipertahankan sebagai adapter selama migrasi.

| Fase | Isi | Commit |
|---|---|---|
| **0** | audit, peta route/API/permission, baseline test & performa | `chore(apotik-uiux): document current state and test baseline` |
| **1** | design token, breakpoint, context bar, page header, status pill, state loading/empty/error, golden dasar | `feat(apotik-uiux): add adaptive apotik design system and shell` |
| **2** | dashboard operasional berbasis prioritas | `feat(apotik-dashboard): add pharmacy operational command center` |
| **3** | POS desktop 3 area + mobile 1 kolom, mode switcher, kartu obat, keranjang, hold/resume | `feat(apotik-pos): modernize OTC and prescription sales workspace` |
| **4** | antrean resep, telaah klinis, dispensing, racikan (sebatas API) | `feat(apotik-rx): prescription queue and dispensing` |
| **5** | persediaan, batch/FEFO, penerimaan PBF (pecah file besar) | `feat(apotik-inventory): batch, expiry and procurement workspace` |
| **6** | pembayaran, perangkat, sinkronisasi | `feat(apotik-payment): payment, device and sync` |
| **7** | laporan & tutup shift | `feat(apotik-reports): reconciliation and shift close` |
| **8** | hardening: a11y, performa, golden lengkap, dokumentasi | `chore(apotik-uiux): hardening and full golden coverage` |

Setelah SETIAP fase: `dart format` → `flutter analyze` → test terkait.

## Batas jujur

Fase 4–7 hanya dapat diselesaikan **sebatas kemampuan API aktual**
(lihat `02-api-action-map.md`). Fitur yang butuh backend baru dicatat sebagai
integration request IR-01..IR-10, TIDAK dipalsukan sebagai sukses.
