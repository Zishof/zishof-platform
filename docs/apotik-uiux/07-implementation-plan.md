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
| **7** ◑ | rekonsiliasi kas apotek (rekap per metode + hitung laci); penyimpanan tutup shift menunggu IR-06 | sebagian |
| **8** ✅ | hardening: kontras WCAG terukur, skala teks 2,0×, penjaga performa daftar, 8 golden komponen | selesai |

Setelah SETIAP fase: `dart format` → `flutter analyze` → test terkait.

## Status per 19 Agustus 2026

Suite test: **71 (baseline) → 285 hijau**. Analyze bersih di seluruh fase.

**Fase 0-6 SELESAI.** Backend IR-01/IR-02/IR-05/IR-07 sudah diimplementasikan
(SVN) dan dipakai UI; Fase 6 menambah `adaKembalian`/`online` pada
`apotik_cara_bayar_list` (r83182).

**Yang Fase 6 perbaiki, bukan sekadar percantik.** Kegagalan JARINGAN saat
membayar dulu ditandai "gagal" — padahal saat itu kasir tidak tahu apakah
server sempat membukukan transaksi. Sekarang keadaan itu menjadi
`paidUnsynced`: keranjang tidak dikosongkan, pembayaran masuk antrean yang
selamat dari aplikasi ditutup, dan kasir memastikannya lewat "Periksa ke
server" yang mengirim ulang payload dengan kode idempoten yang sama.

**Fase 7 sebagian.** Pertanyaan terbuka IR-06 kini terjawab dengan bukti:
laporan tutup kas POS umum membaca ledger POS, yang tidak memuat penjualan
apotek — memakainya apa adanya akan melaporkan tunai apotek Rp 0 dan selisih
kas sebesar seluruh penerimaan. Karena itu Fase 7 menambah aksi baca sendiri
(`apotik_laporan_pembayaran`, r83210) dan tab **Rekonsiliasi Kas** yang
menghitung kas seharusnya dari rekap itu. Yang sengaja TIDAK dibuat: tombol
"Tutup Shift" — penutupannya belum dapat disimpan di server, dan tombol yang
tidak menyimpan apa pun lebih berbahaya daripada tidak ada.

**Fase 8 selesai.** Hardening menemukan cacat nyata, bukan sekadar merapikan:
label pill status hanya mencapai 3,0-3,3:1 (di bawah ambang WCAG untuk teks)
dan `textSecondary` 4,39:1 di atas latar redup; enam tempat meluber pada skala
teks 2,0× yang lazim dipakai pengguna lanjut usia. Semuanya diperbaiki dan
kini dijaga test yang MENGHITUNG kontras serta memasang layar pada skala besar.

**IR-11 dikerjakan setelah Fase 8** (AIS r83255): uang diterima dan kembalian
kini dibukukan per baris pembayaran, dan satu transaksi boleh dibayar dengan
beberapa metode sekaligus. Pagar utamanya: jumlah seluruh baris wajib sama
dengan total — tanpa itu penjualan bisa terbukukan dengan uang yang tidak
pernah lengkap, dan selisihnya baru ketahuan saat tutup kas.

**Sisa pekerjaan bukan lagi soal UI**, melainkan keputusan integrasi:
IR-03 (basis pengetahuan obat), IR-04 (racikan), IR-06 (penyimpanan shift),
IR-09 (PO & bukti suhu), IR-10 (metrik SLA).

## Batas jujur

Fase 4–7 hanya dapat diselesaikan **sebatas kemampuan API aktual**
(lihat `02-api-action-map.md`). Fitur yang butuh backend baru dicatat sebagai
integration request IR-01..IR-10, TIDAK dipalsukan sebagai sukses.
