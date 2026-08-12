# Evidence P3 — Kulakan, AP, laporan pembelian (Layar 20–29), 2026-08-12

## Commit (pushed)

| Repo | Commit | Isi |
|---|---|---|
| AIS | `0cc88638` | Entity PayableFakturInfo (1:1 PengadaanFaktur, CASH/DP/CREDIT + termin + jatuh tempo + dibayar awal) + PembayaranHutangSupplier (metode + BG/bank/tanggalBG pola TRAN_HUT.DBF + kodeUnik idempoten) + AlokasiPembayaranHutangSupplier; SalesInventoryPayableHelper 8 aksi; dispatcher; hibernate.cfg.xml |
| zishof-platform | `4aaec16` | hutang_supplier_screen 5 tab + voucher/faktur PDF client-side + menu kunci `hutang` |

## Keputusan desain kunci

1. **Register event, bukan saldo tersimpan** (Matriks layar 22): outstanding per faktur =
   `totalFakturFinal − dibayarAwal − Σalokasi` — selalu dihitung, tidak pernah diedit bebas.
2. **Faktur kulakan lama tanpa info = CASH lunas** — alur kulakan lama memang tunai; TIDAK
   ada hutang yang muncul diam-diam dari data lama; backfill kredit dilakukan sadar per
   faktur lewat `si_purchase_terms_save`.
3. **Idempoten**: `kode_unik` dibuat SEKALI saat form pembayaran dibuka; retry Simpan
   memakai kunci sama; server mengembalikan pembayaran pertama (`idempotentReplay`) —
   termasuk balapan constraint unik.
4. **Atomicity**: validasi & insert alokasi dalam SATU transaksi dgn `SELECT … FOR UPDATE`
   per faktur — dua pembayaran bersamaan tidak bisa sama-sama melewati outstanding.
5. **Kontrak kulakan lama TIDAK diubah** — info hutang hidup di entity extension; varian
   POS existing tidak terdampak.

## Build & test yang DIJALANKAN

- `mvn -o compile` EXIT=0 (setelah slice server).
- `flutter analyze` 0 error (37 issue total = baseline + 2 info pola existing).
- Build release pasca-P3 (dijalankan nyata, 2026-08-12):
  - `flutter build apk --release --flavor inventorySales -t lib/main_inventory_sales.dart
    --dart-define=...` → SUKSES 198.3s, `app-inventorysales-release.apk` (82.4MB).
  - `flutter build windows --release -t lib/main_inventory_sales.dart --dart-define=...`
    → SUKSES 105.8s.

## Batasan (jujur — tidak diklaim DONE)

1. UAT runtime + uji idempoten/atomik nyata menunggu deploy server (task #15).
2. Batch/expiry/pajak per baris pembelian + input termin langsung di KulakanScreen +
   tombol deep-link Hutang di layar Kulakan menyusul (layar itu dibagi dgn varian POS;
   perluasan harus lewat parameter opsional agar kontrak lama utuh).
3. Reversal pembayaran posted + audit reprint voucher/watermark menyusul.
4. PDF/Excel laporan pembelian menyusul (tab menampilkan tabel + ringkasan).
