# 07 — Rencana Implementasi

Mengikuti §20 dokumen perintah. **Tanpa big-bang rewrite**: class & menu publik
existing dipertahankan sebagai adapter selama migrasi.

| Fase | Isi | Commit |
|---|---|---|
| **0** ✅ | audit, peta route/API/permission, baseline test & performa | `12a76c5` |
| **1** ✅ | design token, breakpoint, context bar, page header, status pill, state loading/empty/error | `6913f1b` |
| **2** ✅ | dashboard operasional berbasis prioritas | `3a00ba1` |
| **3** ✅ | state machine + mode switcher + panel keranjang (`8469045`); halaman POS 3-area + pemilih batch FEFO IR-02 + `KasirApotikScreen` jadi route adapter | selesai |
| **4** | antrean resep, telaah klinis, dispensing, racikan (sebatas API) | `feat(apotik-rx): prescription queue and dispensing` |
| **5** | persediaan, batch/FEFO, penerimaan PBF (pecah file besar) | `feat(apotik-inventory): batch, expiry and procurement workspace` |
| **6** | pembayaran, perangkat, sinkronisasi | `feat(apotik-payment): payment, device and sync` |
| **7** | laporan & tutup shift | `feat(apotik-reports): reconciliation and shift close` |
| **8** | hardening: a11y, performa, golden lengkap, dokumentasi | `chore(apotik-uiux): hardening and full golden coverage` |

Setelah SETIAP fase: `dart format` → `flutter analyze` → test terkait.

## Status per 19 Agustus 2026

Suite test: **71 (baseline) → 157 hijau**. Analyze bersih di seluruh fase.

**Fase 0-3 SELESAI.** Backend IR-01/IR-02/IR-07 juga sudah diimplementasikan
(SVN) dan dipakai UI.

**Berikutnya: Fase 4** (antrean resep & telaah), lalu Fase 5-8. Ingat batas
jujurnya: telaah klinis, double-check, dan racikan menunggu IR-03/IR-04/IR-05,
jadi Fase 4 hanya dapat menyelesaikan bagian yang API-nya sudah ada
(daftar resep, detail, dan penebusan lewat kasir).

## Batas jujur

Fase 4–7 hanya dapat diselesaikan **sebatas kemampuan API aktual**
(lihat `02-api-action-map.md`). Fitur yang butuh backend baru dicatat sebagai
integration request IR-01..IR-10, TIDAK dipalsukan sebagai sukses.
