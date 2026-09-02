# 07 — Rencana Implementasi

Mengikuti §20 dokumen perintah. **Tanpa big-bang rewrite**: class & menu publik
existing dipertahankan sebagai adapter selama migrasi.

| Fase | Isi | Commit |
|---|---|---|
| **0** ✅ | audit, peta route/API/permission, baseline test & performa | `12a76c5` |
| **1** ✅ | design token, breakpoint, context bar, page header, status pill, state loading/empty/error | `6913f1b` |
| **2** ✅ | dashboard operasional berbasis prioritas | `3a00ba1` |
| **3** ✅ | state machine + mode switcher + panel keranjang (`8469045`); halaman POS 3-area + pemilih batch FEFO IR-02 + `KasirApotikScreen` jadi route adapter | selesai |
| **4** ✅ | antrean resep, daftar periksa pra-serah, dispensing IR-05 (racikan tetap terkunci: IR-04) | selesai |
| **5** ✅ | formularium (editor IR-01), batch/FEFO (IR-02 tulis), penerimaan PBF | `feat(apotik-inventory): batch, expiry and procurement workspace` |
| **6** ✅ | lembar pembayaran + kembalian, laci kas & struk ESC/POS lokal, pemulihan pembayaran yang belum dipastikan | selesai |
| **7** | laporan & tutup shift | `feat(apotik-reports): reconciliation and shift close` |
| **8** | hardening: a11y, performa, golden lengkap, dokumentasi | `chore(apotik-uiux): hardening and full golden coverage` |

Setelah SETIAP fase: `dart format` → `flutter analyze` → test terkait.

## Status per 19 Agustus 2026

Suite test: **71 (baseline) → 224 hijau**. Analyze bersih di seluruh fase.

**Fase 0-6 SELESAI.** Backend IR-01/IR-02/IR-05/IR-07 sudah diimplementasikan
(SVN) dan dipakai UI; Fase 6 menambah `adaKembalian`/`online` pada
`apotik_cara_bayar_list` (r83182).

**Yang Fase 6 perbaiki, bukan sekadar percantik.** Kegagalan JARINGAN saat
membayar dulu ditandai "gagal" — padahal saat itu kasir tidak tahu apakah
server sempat membukukan transaksi. Sekarang keadaan itu menjadi
`paidUnsynced`: keranjang tidak dikosongkan, pembayaran masuk antrean yang
selamat dari aplikasi ditutup, dan kasir memastikannya lewat "Periksa ke
server" yang mengirim ulang payload dengan kode idempoten yang sama.

**Berikutnya: Fase 7** (laporan & tutup shift) lalu Fase 8. Tutup shift
menunggu keputusan IR-06 (pakai ulang `sesi_kas_*` atau aksi apotik sendiri),
jadi bagian itu tidak boleh dikarang lebih dulu.

## Batas jujur

Fase 4–7 hanya dapat diselesaikan **sebatas kemampuan API aktual**
(lihat `02-api-action-map.md`). Fitur yang butuh backend baru dicatat sebagai
integration request IR-01..IR-10, TIDAK dipalsukan sebagai sukses.
