# 07 — Rencana Implementasi

Mengikuti §20 dokumen perintah. **Tanpa big-bang rewrite**: class & menu publik
existing dipertahankan sebagai adapter selama migrasi.

| Fase | Isi | Commit |
|---|---|---|
| **0** ✅ | audit, peta route/API/permission, baseline test & performa | `12a76c5` |
| **1** ✅ | design token, breakpoint, context bar, page header, status pill, state loading/empty/error | `6913f1b` |
| **2** ✅ | dashboard operasional berbasis prioritas | `3a00ba1` |
| **3** 🔶 | state machine POS + mode switcher + panel keranjang **selesai** (`8469045`); **sisa: merakit halaman POS 3-area dan mengalihkan `KasirApotikScreen` ke sana** | sebagian |
| **4** | antrean resep, telaah klinis, dispensing, racikan (sebatas API) | `feat(apotik-rx): prescription queue and dispensing` |
| **5** | persediaan, batch/FEFO, penerimaan PBF (pecah file besar) | `feat(apotik-inventory): batch, expiry and procurement workspace` |
| **6** | pembayaran, perangkat, sinkronisasi | `feat(apotik-payment): payment, device and sync` |
| **7** | laporan & tutup shift | `feat(apotik-reports): reconciliation and shift close` |
| **8** | hardening: a11y, performa, golden lengkap, dokumentasi | `chore(apotik-uiux): hardening and full golden coverage` |

Setelah SETIAP fase: `dart format` → `flutter analyze` → test terkait.

## Status per 19 Agustus 2026

Suite test: **71 (baseline) → 138 hijau**. Analyze bersih di seluruh fase.

**Sisa Fase 3** (dikerjakan berikutnya): merakit `ApotikPosPage` tiga area
(konteks+mode | katalog | keranjang) untuk desktop dan satu kolom + sticky
action untuk mobile, lalu mengalihkan `KasirApotikScreen` ke sana sebagai
route adapter. Sheet pilih-batch (FEFO) dan pilih-resep yang sudah terbukti
di layar lama akan DIPINDAH, bukan ditulis ulang, agar pagar keselamatannya
tidak berubah.

## Batas jujur

Fase 4–7 hanya dapat diselesaikan **sebatas kemampuan API aktual**
(lihat `02-api-action-map.md`). Fitur yang butuh backend baru dicatat sebagai
integration request IR-01..IR-10, TIDAK dipalsukan sebagai sukses.
