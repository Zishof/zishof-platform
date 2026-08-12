# Evidence P4–P7 — AR, SPJ/Sesi Nota Sales, Finance, Offline Outbox (2026-08-12)

## Commit (semua pushed)

| Repo | Commit | Isi |
|---|---|---|
| AIS | `f1f63aa9` (+entity di `a39c291d`*) | P4: 5 entity AR + SalesInventoryReceivableHelper 11 aksi (sales order lifecycle, receivable, collection, aging) |
| AIS | `0eb8598e` | P5: 8 entity SPJ/Sesi + SalesInventoryTripHelper 20 aksi + collection ber-sesi + seed kategori biaya |
| AIS | `fdd04702` | P6: SalesInventoryFinanceHelper (COA/jurnal reuse akunting existing + laba kotor snapshot + laba/rugi varian) |
| zishof-platform | `1f823e1` | P4 Flutter: penjualan_sales_screen + piutang_screen 5 tab + kwitansi PDF |
| zishof-platform | `e290f52` | P5 Flutter: spj_screen + nota_sales_screen + laporan sesi PDF |
| zishof-platform | `0000c3c` | P6 Flutter: kas_jurnal_screen + laba_rugi_screen + PDF |
| zishof-platform | `32c9cc1` | P7: core_db v4 outbox_is + OutboxIs service + wiring |

*) Insiden shared-checkout terulang: commit "ok" sesi paralel (a39c291d) menyapu 5 entity
P4 + hibernate.cfg.xml yang sedang staged — tidak ada data hilang, hanya terpecah dua
commit. Mitigasi pathspec eksplisit tetap dipakai di semua commit kami.

## Build & test yang DIJALANKAN

- `mvn -o compile` EXIT=0 setelah P4, P5, dan P6 (masing-masing).
- `flutter analyze` 37 issue (persis baseline, 0 error) + `flutter test` lulus setelah
  tiap slice Flutter (P4/P5/P6/P7).

## Keputusan desain baru (D-12..D-14)

- **D-12**: saldo piutang customer = ledger POS existing (masuk-sebagai-hutang −
  pembayaran_hutang) **+** outstanding faktur AR baru — dua sub-ledger dijumlah, tidak
  dicampur, tanpa duplikasi pencatatan.
- **D-13**: transisi order TERKIRIM **tidak** menggerakkan stok di P4; movement fisik
  dicatat lewat SPJ "barang dibawa" (P5) supaya tidak dobel-hitung.
- **D-14**: stok mobil sales dicatat penuh di ledger SPJ (dimuat/terjual/kembali/rusak/
  hilang + rekonsiliasi wajib habis sebelum tutup); INTEGRASI pemotongan stok toko ke
  formula stok POS produksi menunggu keputusan UAT (kebijakan risiko dokumen input).
- **P6 reuse**: COA = akunting.akun & jurnal = akunting.transaksi existing (tanpa tabel
  akuntansi kedua); laporan keuangan penuh tetap lewat `laporan_keuangan_katalog`.
  Laba/rugi varian dilabeli eksplisit "ringkasan operasional".
- **P7**: outbox `outbox_is` sengaja TERPISAH dari `transaksi_pending` karena flush POS
  existing mengirim semua baris pending ke aksi `bayar`. Hanya aksi idempoten
  ber-kode_unik yang boleh diantre; penolakan bisnis tidak diretry buta.

## Batasan jujur (belum DONE penuh)

1. UAT runtime seluruh fase menunggu deploy Tomcat (commit AIS di atas) + akun uji
   3 role (task #15); termasuk uji idempoten/lock konkuren di server nyata.
2. D-14: movement stok toko dari SPJ belum menyentuh formula stok POS — blocker
   keputusan UAT, dicatat di ledger TRIP-002.
3. Reversal dokumen posted (penerimaan/biaya/kwitansi) menyusul; koreksi saat ini =
   dokumen pembalik manual.
4. APK masih debug-sign (keystore produksi belum tersedia — uat-required #11).
5. Uji offline outbox nyata (perangkat + server) belum dijalankan; logika teruji lewat
   kompilasi + pola idempoten server.
