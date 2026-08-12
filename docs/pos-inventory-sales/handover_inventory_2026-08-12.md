# HANDOVER — Varian "eBisnis Inventory & Sales" (2026-08-12)

> Untuk sesi/komputer berikutnya. Semua yang disebut di sini SUDAH di-push;
> cukup `git pull` di kedua repo. Baca bersama `01-gap-ledger.csv` (status per
> layar) dan `evidence/*/README.md` (bukti per fase).

## 1. Apa proyek ini

Transisi **48 layar legacy FoxPro "INVENTORY CONTROL"** menjadi varian produk
**eBisnis Inventory & Sales** (server AIS yang sama + klien Flutter
Windows/Android dari monorepo zishof-platform). Dokumen kontrak:
`Panduan-Transisi-48-Layar...v2.pdf` + `Matriks-Paritas-Komponen-48-Layar-v2.csv`
(SHA256 di `source-manifest.sha256` — versi di Downloads == versi acuan).

## 2. Status: SELESAI (fungsional) — P0..P10

| Fase | Isi | Commit kunci |
|---|---|---|
| P0 | Baseline + audit + gap ledger 48 layar | zishof (awal proyek) |
| P1 | Fondasi varian: dispatcher `si_*`, ActorContext fail-closed, seed role/menu, flavor Windows+Android | AIS 1d7a82dc dkk |
| P2 | Master supplier/customer/sales, persediaan+kartu stok, opname, harga versi, laporan+PDF/Excel, ekspor | lihat ledger |
| P3 | AP hutang supplier (register event, pembayaran alokasi idempoten, aging, voucher) | lihat ledger |
| P4 | AR: sales order lifecycle (order≠invoice), piutang, collection idempoten, aging cust/sales | AIS f1f63aa9 (+a39c291d), zishof 1f823e1 |
| P5 | SPJ + Sesi Nota Sales (barang/nota dibawa, biaya, kulakan sesi, kas append-only, DUA rumus, tutup ber-approval) | AIS 0eb8598e, zishof e290f52 |
| P6 | Finance: COA+jurnal reuse `akunting.*` existing, laba kotor HPP snapshot, laba/rugi varian | AIS fdd04702, zishof 0000c3c |
| P7 | Outbox offline typed `outbox_is` (core_db v4; TERPISAH dari transaksi_pending!) | zishof 32c9cc1 |
| P8 | Rilis v1.32.0/v1.33.0 prerelease + ledger penuh | tag `inventory-sales-v1.33.0` |
| P9 | Audit matriks → 4 gap ditutup: rekap penjualan per barang (si_receivable_report), HPP Tambah % (hpp_tambah_persen), P&L per baris faktur+jual rugi (si_profit_loss_detail), Riwayat Audit Envers (si_audit_history) | AIS aa9dd08e, zishof 6a7178f+818bcc2 |
| P10 | Reversal dokumen posted (AP/AR/biaya, dokumen pembalik idempoten `REV-*`), siklus BG DITERIMA→CAIR/TOLAK (TOLAK=auto-reversal), register riwayat cetak (LogCetak + si_print_log_*) | AIS **d59fbe6d**, zishof **63d0021** |

Total ±86 aksi `si_*` di `SalesInventoryApiDispatcher` (helpers: Master,
Stock, Price, Payable, Receivable, Trip, Finance, Reversal, DbfImport).
Klien: 15 layar varian di `apps/ebisnis/lib/screens/inventory_sales/` +
menu fail-closed di `app_shell.dart`/`app_drawer.dart` (16 kunci menu server).

## 3. Repo & branch

| Repo | Path lokal (komputer lama) | Branch | HEAD terakhir |
|---|---|---|---|
| AIS (server) | `C:\opt\AIS\ais\src\main` | `feat/new-ui-rbac-role-user` | d59fbe6d |
| zishof-platform (Flutter) | `C:\opt\CodeBaseDesktopDanMobile` | `main` | 63d0021 (+handover ini) |
| SVN | AIS di-mirror otomatis dari git (svn://38.47.178.34) — tidak perlu aksi manual; `desktop-pos-electron` working copy SVN, TIDAK disentuh proyek ini | — | — |

⚠️ Dua–tiga sesi Codex/Claude paralel bekerja di working copy YANG SAMA:
selalu commit dgn **pathspec eksplisit** (jangan `git add -A`), segera setelah
selesai; lihat memori `codex-concurrent-session-overwrite-commit-fast`.
Insiden hari ini: commit "ok" sesi paralel menyapu 5 entity P4 (tidak hilang,
hanya pindah commit); remote AIS juga sempat mundur (force-push sesi lain) dan
sudah dipulihkan.

## 4. Yang BELUM selesai (urutan prioritas utk sesi berikutnya)

1. **UAT runtime 48 layar** — satu-satunya penentu "LULUS" matriks.
   - Butuh: **deploy Tomcat commit AIS `d59fbe6d`** + **akun uji** (min. 1
     Pemilik `pemilik_sales_inventory`; ideal + `sales_keliling`; role
     ter-seed otomatis saat servlet start).
   - Jalankan: `docs/pos-inventory-sales/uat/uat_runtime_48layar.ps1`
     (±40 skenario: idempoten replay, overpayment ditolak, transisi ilegal
     ditolak, dobel-bawa nota ditolak, dua rumus sesi angka pasti, laba kotor
     24000 dari HPP snapshot, impor DBF 2× run). Evidence otomatis ke
     `evidence/uat/uat-runtime-<stamp>.json`. Exit 0 = semua PASS.
2. **P10 Flutter sisa (server sudah siap semua)**: tombol Reversal + BG di tab
   Pembayaran `hutang_supplier_screen.dart` (pakai `statusDok`/`statusBg` yang
   kini ada di `si_payable_payment_history`; aksi `si_payable_payment_reverse`,
   `si_payable_bg_status`) • tombol reversal biaya di `nota_sales_screen.dart`
   (baris biaya kini ber-`statusDok`; aksi `si_expense_reverse`) • wiring
   `si_print_log_create` di cetak laporan sesi/laba-rugi/rekap/voucher AP
   (pola: lihat `_cetakKwitansi` di `piutang_screen.dart`) • UI daftar
   `si_print_log_list` (mis. tab kecil di Konfigurasi, Pemilik/Admin).
3. **Rilis berikutnya** membawa P9+P10 klien (pubspec dipegang sesi paralel,
   sudah 1.33.5+63; pakai skrip `tool/build_apk_inventory_sales.ps1` +
   `tool/build_windows_inventory_sales.ps1 -Installer`, publish tag
   `inventory-sales-vX.Y.Z` **--prerelease** agar `/latest` POS tak terganggu).
4. **Keputusan user yang digantung**: D-14 (pemotongan stok toko dari SPJ —
   jangan sentuh formula stok POS produksi tanpa keputusan UAT); entri jurnal
   double-entry penuh di varian (sekarang reuse web akunting existing);
   keystore produksi Android (APK masih debug-sign); template Excel harga
   (impor DBF sudah ada).

## 5. Keputusan desain penting (jangan dilanggar)

- **Register event**: outstanding hutang/piutang SELALU dihitung
  (`total − dibayar_awal − Σalokasi`), tidak pernah disimpan; "lunas" = filter
  visual; dokumen posted TIDAK dihapus → **reversal = dokumen pembalik negatif**
  ber-kodeUnik `REV-<jenis>-<id>` (P10), asal ditandai DIBATALKAN.
- **Idempoten**: semua create transaksi ber-`kode_unik` unik; retry = replay.
  Outbox offline hanya utk aksi idempoten (`OutboxIs.aksiDidukung`).
- **RBAC fail-closed**: prefix `si_` tak dikenal = TOLAK (PosApi
  `bolehAksesActionKantin`); scope SALES_KELILING = data miliknya
  (`ctx.salesId`), Pemilik/POS = `ctx.tokoId`.
- **D-12**: saldo piutang customer = ledger POS lama + outstanding AR baru
  (dua sub-ledger dijumlah). **D-13**: order TERKIRIM tidak menggerakkan stok
  (movement via SPJ). **Sesi CLOSED = beku**: reversal atas dokumen sesi
  tertutup DITOLAK (koreksi = dokumen penyesuaian baru).
- **Entity baru**: WAJIB `@Column` eksplisit snake_case (implicit naming
  Hibernate MENEMPEL camelCase!), daftar di `hibernate.cfg.xml`, `@Audited`
  (kecuali tabel log), BigDecimal utk uang, nomor dokumen dari id pasca-insert
  (`PREFIX-<toko>-<id 6 digit>`), tanpa MAX+1.
- **DDL**: serahkan `hbm2ddl.auto=update` — JANGAN sarankan ALTER TABLE manual.

## 6. Verifikasi cepat di komputer baru

```bash
cd <AIS>/src/main && git pull && mvn -o compile        # EXIT=0
```
```bash
cd <zishof-platform> && git pull && cd apps/ebisnis && flutter analyze && flutter test
```
(analyze: pastikan **0 error**; jumlah info ±38 tergantung pekerjaan paralel.)

## 7. Rilis & artefak

- GitHub release: `inventory-sales-v1.33.0` (prerelease; APK+installer+SHA256SUMS)
  — https://github.com/Zishof/zishof-platform/releases/tag/inventory-sales-v1.33.0
- Server endpoint dev: `https://dev.ecampus.id/ecampus/Api_eBisnis`
  (deploy user tadi pagi BELUM memuat P9/P10 — perlu redeploy `d59fbe6d`).
- Ikon/branding varian: `assets/images/inventory_sales/`; installer Inno di
  `apps/ebisnis/installer/` (exclude `ebisnis*.exe` varian lain).
