# Eksekusi lanjutan seluruh fase blueprint terpadu

Tanggal: 26 Agustus 2026

## Outcome saat ini

Pekerjaan ini mengubah blueprint menjadi fondasi kode yang dapat diuji, bukan menyatakan semua modul bisnis sudah selesai. Registry menu dan aksi lintas fase sudah tervalidasi, kontrak bridge identitas item/UOM/lokasi, ledger/saldo, reservasi idempoten, shadow-write pasca-commit, rekonsiliasi read-only, produksi, Accounts Payable, posting akuntansi, serta read model control tower berbasis snapshot dan watermark sudah tersedia. Preflight read-only dan seluruh draft migration tetap hanya disiapkan untuk review. Tidak ada DDL/DML yang dijalankan ke database produksi dan tidak ada build yang dirilis.

## Implementasi kode yang selesai

### Registry menu dan hak aksi

- `EbisnisMenuBlueprintRegistry` memuat 101 entri menu terstruktur berikut parent, alias, dan aksi workflow.
- Alias yang bertabrakan telah dipisahkan: `pengadaan_tagihan` hanya menunjuk menu tagihan vendor yang kanonis.
- `edit_draft` menjadi aksi kanonis tersendiri; tidak lagi runtuh menjadi `update`.
- Registry aksi tetap menyediakan alias kompatibilitas untuk istilah UI lama.
- Mirror `src/main/src` dan `src/main/java` identik byte-for-byte.

### Kontrak posting persediaan, domain ledger, dan adapter PostgreSQL Fase 3

- `InventoryMovementCommand`: immutable, tervalidasi, dan defensive-copy untuk tanggal.
- `InventoryMovementResult`: membedakan posting baru, retry yang sudah pernah diposting, dan penolakan.
- `InventoryPostingPort`: batas aplikasi untuk adaptor writer existing dan implementasi ledger berikutnya.
- `InventoryBalanceKey` mengunci saldo per tenant/lokasi/item/lot tanpa mencampur scope.
- `InventoryLedgerRecord` memverifikasi aritmetika saldo sebelum + mutasi = saldo sesudah.
- `InventoryLedgerRepository` menetapkan batas repository atomik dan pencarian retry idempoten.
- Kontrak reservasi memisahkan RESERVE, RELEASE, dan CONSUME beserta idempotency key per operasi.
- Draft skema PostgreSQL mencakup lot, saldo, ledger, current reservation, dan reservation event. Draft belum dijalankan.
- Adapter JDBC PostgreSQL sudah dibuat dengan transaksi atomik, `SELECT ... FOR UPDATE`, unique-key idempotency, deteksi konflik payload, rollback, dan penutupan resource pada `finally`.
- Harness integrasi dua koneksi sudah tersedia, tetapi eksekusi database nyata masih `SKIPPED` sampai URL database UAT khusus diberikan. Adapter belum dihubungkan ke writer produksi.
- `InventoryShadowWriteService` menyediakan feature flag per writer yang default nonaktif dan hanya boleh dipanggil setelah commit legacy berhasil.
- Hasil shadow-write membedakan DISABLED, POSTED, ALREADY_POSTED, REJECTED, dan FAILED; kegagalan shadow maupun audit tidak membatalkan transaksi legacy.
- `InventoryReconciliationService` membandingkan saldo legacy dengan ledger per tenant/lokasi/item/lot secara read-only tanpa koreksi saldo otomatis.

### Kontrak master identitas Fase 2

- `InventoryItemReference` membedakan Produk, MasterAsset, dan item SIRS dengan tenant, tipe sumber, ID, serta scope sumber.
- `InventoryLocationReference` membedakan Toko, Gudang, Lokasi Asset, dan Bin; ID numerik yang sama tidak dianggap lokasi yang sama.
- `InventoryUomConversion` melakukan konversi rasional `BigDecimal` dengan numerator/denominator positif, scale, dan rounding mode eksplisit.
- `InventoryIdentityResolver` menjadi port bagi adaptor legacy untuk memperoleh ID item dan lokasi kanonis.
- Tidak ada inferensi mapping hanya dari kesamaan ID/nama, dan tidak ada skema atau data produksi yang diubah.

### Fondasi AP dan akuntansi Fase 10

- Invoice vendor baru memiliki aggregate kanonis dan tidak lagi dirancang menulis ke `SaldoAwalMasterAsset`.
- Three-way match mengikat baris invoice dengan detail PO dan penerimaan/BAST; selisih masuk `MATCH_EXCEPTION` dan tidak dipaksa lolos.
- Alokasi pembayaran menjembatani `ProsesTransfer`/`DaftarPengajuanTransfer` secara idempoten dan menolak pembayaran berlebih.
- Credit note mengurangi saldo terbuka tanpa menghapus histori invoice.
- Posting invoice/pembayaran mempunyai source key dan idempotency key; retry tidak menggandakan jurnal.
- Koreksi jurnal memakai reversal bernilai lawan, sedangkan period lock mencegah posting pada periode tertutup.
- Draft skema AP, matching, dispute, schedule, allocation, posting, valuation, period lock, dan audit event tersedia untuk review DBA; belum dijalankan.

### Read model laporan dan control tower Fase 11

- Halaman awal hanya membaca snapshot terakhir; cache kosong menghasilkan snapshot `STALE` tanpa menjalankan agregasi besar ke tabel OLTP.
- Refresh agregasi dilakukan secara eksplisit melalui port read-model, menyimpan snapshot immutable, status, waktu pembentukan, dan watermark sumber.
- Setiap KPI wajib memiliki kode unik, owner, sumber data, rute drill-down, dan kueri rekonsiliasi.
- Paging/limit alert divalidasi pada server dengan batas 1–500 baris.
- Ekspor mengambil snapshot `READY` yang sama berdasarkan ID sehingga angka kartu, grid, drill-down, dan ekspor tidak berbeda waktu baca.
- Draft skema snapshot, metric, alert, indeks, constraint, dan rollback tersedia untuk review DBA; belum dijalankan.

## UAT yang sudah lulus

Kompilasi target dilakukan dengan `javac -source 1.7 -target 1.7`.

- `EbisnisMenuActionRegistryUat`: **LULUS**.
- `EbisnisMenuBlueprintRegistryUat`: **LULUS, 101 entri**.
- `InventoryMovementContractUat`: **LULUS**.
- `InventoryMasterReferenceContractUat`: **LULUS**, termasuk collision lintas tipe dan round-trip UOM.
- `InventoryLedgerDomainContractUat`: **LULUS**, termasuk validasi aritmetika, defensive date, kontrak reservasi, dan dua thread dengan kunci idempoten sama.
- `InventoryShadowWriteAndReconciliationUat`: **LULUS**, termasuk default nonaktif, retry idempoten, isolasi kegagalan shadow/audit, serta rekonsiliasi matched/mismatch/failed.
- `PostgreSqlInventoryLedgerIntegrationUat`: **SKIPPED secara aman** karena database UAT khusus belum dikonfigurasi; harness berhasil dikompilasi Java 1.7.
- `WarehouseInboundServiceUat`: **LULUS**, termasuk status receipt, QC partial, lot wajib, putaway lengkap, kuantitas seimbang, dan retry idempoten.
- `ProductionServiceUat`: **LULUS**, termasuk scaling BOM/loss, issue-return bahan, receipt output, waste, costing, transisi workflow, null guard, dan retry idempoten.
- `AccountsPayableServiceUat`: **LULUS, 26 assertion**, termasuk invoice duplikat, three-way match, exception, pembayaran parsial/lunas, overpayment, credit note, posting idempoten, reversal, period lock, dan rekonsiliasi subledger.
- `ControlTowerServiceUat`: **LULUS, 22 assertion**, termasuk initial load tanpa agregasi OLTP, snapshot stale/ready, watermark, limit server-side, metadata KPI, snapshot ekspor yang sama, immutable list, cache, dan penolakan KPI duplikat.
- Tujuh file shadow-write dan rekonsiliasi pada kedua mirror source: **identik SHA-256**.
- Lima file domain WMS inbound pada kedua mirror source: **identik SHA-256**; output kompilasi terisolasi dan tidak ada `.class` di samping `.java`.
- Dua belas file domain produksi pada kedua mirror source: **identik SHA-256**; output kompilasi terisolasi dan tidak ada `.class` di samping `.java`.
- Sebelas file domain AP dan akuntansi pada kedua mirror source: **identik SHA-256**; output kompilasi terisolasi dan tidak ada `.class` di samping `.java`.
- Tiga file domain control tower pada kedua mirror source: **identik SHA-256**; output kompilasi terisolasi dan tidak ada `.class` di samping `.java`.
- Dua file fondasi migrasi/rollout pada kedua mirror source: **identik SHA-256**; self-test Java 1.7 lulus **57 pemeriksaan**, output kompilasi terisolasi, dan tidak ada `.class` di samping `.java`.
- Dua file fondasi stabilisasi/dekomisioning pada kedua mirror source: **identik SHA-256**; self-test Java 1.7 lulus **43 pemeriksaan**, output kompilasi terisolasi, dan tidak ada `.class` di samping `.java`.
- Dua file journal evidence migrasi immutable pada kedua mirror source: **identik SHA-256**; self-test Java 1.7 lulus **25 pemeriksaan**, regresi Fase 13–14 tetap lulus **57/43 pemeriksaan**, output kompilasi terisolasi, dan tidak ada `.class` di direktori paket Java.
- Empat file repository durable dan evidence gate Fase 16: self-test Java 1.7 lulus **30 pemeriksaan**; regresi Fase 13–15 tetap lulus **57/43/25 pemeriksaan**, output kompilasi terisolasi, dan source tree bersih dari `.class`.

Build Ant penuh belum menjadi bukti kelulusan karena konfigurasi existing menunjuk `C:\opt\AIS\ais\web\WEB-INF\lib`, sedangkan library aktual berada di `src/main/webapp/WEB-INF/lib`. Hambatan build ini tidak boleh disamarkan sebagai kegagalan kontrak target maupun dianggap selesai tanpa perbaikan terpisah.

## Matriks fase 0–16

| Fase | Status | Yang sudah ada | Gerbang sebelum lanjut/cutover |
|---|---|---|---|
| 0. Baseline & governance | Parsial | Dokumen blueprint, ADR, register writer, inventaris route | Golden snapshot, owner modul, rollback runbook, baseline performa |
| 1. Menu, route, aksi, role | Fondasi kode selesai | Registry 101 menu, aksi granular, alias, UAT | Seed DB, adaptor UI/JSP/ZK/Desktop/Android, integrasi runtime `TbmroleAction`, audit admin |
| 2. Identitas item, UOM, lokasi | Kontrak kode selesai; skema pending | Referensi item/lokasi bertipe, konversi UOM, resolver port, ADR, SQL preflight read-only, UAT | Jalankan preflight di target, putuskan mapping `Produk`/`MasterAsset`, DDL review, migrasi kering, adaptor resolver |
| 3. Ledger, saldo, lot, reservasi | Adapter dan fondasi shadow/reconciliation selesai; runtime staging/pilot pending | Posting port, balance key, ledger contract, reservasi, adapter JDBC atomik, harness dua koneksi, shadow-write pasca-commit, rekonsiliasi read-only, ADR, preflight, migration draft | Review/jalankan DDL staging, integration test dua koneksi sampai LULUS, pilot shadow-write, rekonsiliasi nol mismatch |
| 4. Replenishment outlet | Fondasi planner read-only selesai; persistence/workflow pending | Kontrak request/line/plan, availability port, pemisahan alokasi gudang dan shortage procurement, validasi serta UAT Java 1.7 | Fase 2–3 stabil; skema stock request, adapter balance, reservasi idempoten, approval, adapter shortage-to-PR, dan UAT database |
| 5. Konsolidasi procurement | Adapter persistensi dan draft migration selesai; aktivasi staging/workflow pending | Draft PR bertipe, adapter Hibernate ke PR existing, resolver legacy, bridge metadata/idempotensi, hanya shortage yang diteruskan, dan UAT Java 1.7 | Review/jalankan bridge DDL staging, resolver konkret, UAT transaksi dan concurrency, approval, PO, dan invoice vendor kanonis |
| 6. WMS inbound | Fondasi kontrak selesai; migrasi/runtime pending | Receipt/QC/putaway bertipe, posting hanya setelah putaway selesai, idempotency stabil, draft DDL, UAT Java 1.7 | Review/jalankan DDL staging, adapter PO/BAST/lot/lokasi, UAT transaksi dan concurrency, UI serta approval |
| 7. Inventory control | Fondasi kontrak selesai; migrasi/runtime pending | Cycle count approved-only, adjustment ledger idempoten, quarantine status-only, FEFO deterministik, draft DDL, dan UAT Java 1.7 | Review/jalankan DDL staging, adapter transaksi/locking, UI approval/scanner, dan UAT database/concurrency |
| 8. Outbound & distribusi | Selesai (fondasi) | Domain service, reservasi, picking, packing, split shipment, POD, receipt/discrepancy idempoten, draft DDL, dan UAT Java 1.7 | Review/jalankan DDL staging, adapter transaksi/locking, UI scanner, integrasi pengangkut/POD, dan UAT database/concurrency |
| 9. Produksi | Selesai (fondasi) | BOM berversi, work order, issue/return material, output receipt, waste, costing, lot genealogy, draft DDL, dan UAT Java 1.7 | Review/jalankan DDL staging, adapter Unit of Work atomik, bridge legacy, UI, dan UAT database/concurrency |
| 10. AP & akuntansi | Selesai (fondasi) | Invoice kanonis, three-way match, exception, pembayaran/credit note idempoten, posting/reversal, period lock, draft DDL, dan UAT Java 1.7 | Review/jalankan DDL staging, adapter legacy PO/BAST/transfer/jurnal, UAT transaksi/concurrency, shadow-read, dan rekonsiliasi AP–GL |
| 11. Laporan & control tower | Selesai (fondasi) | Snapshot immutable, watermark, KPI metadata, drill-down, server-side limit, ekspor konsisten, draft DDL, dan UAT Java 1.7 | Review/jalankan DDL staging, adapter agregasi per domain, scheduler, UI/ekspor, serta UAT database, performa, timezone, dan paritas |
| 12. Paritas platform | Selesai (fondasi) | Kontrak menu/aksi, permission, paging, idempotensi, optimistic version, error contract, dan profil kapabilitas 4 platform; UAT Java dan Flutter lulus | Pasang adapter layar per layar, jalankan golden flow Desktop/Android/JSP/ZK, lalu sign-off QA dan Product Owner |
| 13. Migrasi & rollout | Selesai (fondasi) | Registry state machine bertahap, scope tenant/lokasi/writer/canary, evidence gate, health gate, rollback eksplisit, kebijakan konservatif default OFF, dan UAT Java 1.7 lulus | Pasang adapter runtime hanya di staging, simpan evidence nyata, lakukan rehearsal rollback, canary terbatas, dan sign-off sebelum aktivasi produksi |
| 14. Stabilisasi & dekomisioning legacy | Selesai (fondasi) | Registry decision-only default OFF, observasi, rekonsiliasi, dependency scan, deprecation, penghentian writer, arsip, restore/replay, dokumentasi, sign-off, removal release terpisah, dan rollback | Selesaikan pilot Fase 13, kumpulkan evidence produksi, jalankan drill restore/replay, lalu ajukan release penghentian writer dan removal secara terpisah |
| 15. Journal evidence migrasi immutable | Selesai (fondasi) | Journal append-only, hash chain SHA-256, idempotensi event, conflict rejection, file locking, durable sync, verifikasi tamper/truncation, dan UAT Java 1.7 | Pasang repository durable/WORM, autentikasi aktor, orkestrator fail-closed Fase 13–14, monitoring, serta restore/replay drill di staging |
| 16. Repository durable & evidence gate | Selesai (fondasi) | Repository terisolasi per scope, gate autentikasi/otorisasi fail-closed, evidence PREPARED/FAILED/APPLIED, retry idempoten, metrik, failure injection, dan UAT Java 1.7 | Pasang adapter WORM produksi, identity provider nyata, observability/retention, crash-recovery dan concurrency test, lalu integrasi rollout risiko rendah di staging |

## Urutan implementasi berikutnya

1. Jalankan dua preflight read-only Fase 2 dan Fase 3 pada salinan/staging database dan simpan output.
2. Finalisasi matriks data nyata `Produk` vs `MasterAsset`, tenant, lokasi, UOM, serta lot berdasarkan kontrak bertipe yang sudah lulus UAT.
3. Review draft DDL Fase 3 dan lengkapi migration Fase 2 yang repeatable serta dapat di-rollback; jangan deploy produksi sebelum sign-off.
4. Jalankan harness adapter PostgreSQL pada database UAT khusus dan buktikan dua koneksi yang mem-posting kunci sama hanya menghasilkan satu ledger/satu perubahan saldo.
5. Setelah UAT database lulus, hubungkan satu writer berisiko rendah ke layanan shadow dengan feature flag tetap default OFF; aktifkan hanya pada pilot dan bandingkan saldo per tenant/lokasi/item/lot sampai nol mismatch.
6. Integrasikan `TbmroleAction` dan menu runtime setelah seed/alias dapat di-rollback.
7. Fondasi planner replenishment dan adapter persistensi shortage-to-PR sudah tersedia; lanjutkan dengan persistence stock request internal, approval, adapter balance, resolver legacy konkret, serta reservasi idempoten setelah gerbang database Fase 3 lulus.
8. Review dan jalankan draft bridge PR di staging, kemudian lakukan UAT transaksi serta dua koneksi dengan idempotency key sama.
9. Fondasi inbound/QC/putaway sudah tersedia; lanjutkan dengan adapter PO/BAST/lot/lokasi dan UAT database sebelum mengaktifkan writer stok.
10. Fondasi inventory control, outbound, produksi, serta AP dan akuntansi sudah tersedia; lanjutkan adapter transaksi/locking, bridge legacy, dan UAT konkurensi/database tanpa mengaktifkan writer produksi.
11. Fondasi Fase 11 sudah tersedia; lanjutkan adapter agregasi domain dan scheduler di staging tanpa mengubah prinsip initial-load dari snapshot.
12. Fondasi kontrak dan UAT teknis Fase 12 sudah selesai; lanjutkan adapter UI Desktop, Android, JSP, dan ZK, golden flow lintas platform, serta sign-off QA/Product Owner.
13. Fondasi Fase 13 sudah tersedia; jalankan urutan `BASELINE` sampai `COMPLETE` melalui registry pada staging, pertahankan feature flag default OFF, simpan bukti tiap gerbang, dan jangan mengubah writer produksi tanpa persetujuan eksplisit serta rollback rehearsal yang lulus.
14. Fondasi Fase 14 sudah tersedia; mulai observasi hanya setelah pilot Fase 13 selesai, tutup exception rekonsiliasi, buktikan dependency nol, dan jangan menghentikan writer atau menghapus artefak sebelum seluruh evidence, restore/replay, dokumentasi, ownership, serta sign-off lengkap.
15. Fondasi Fase 15 sudah tersedia; gunakan journal untuk mengikat evidence pada scope/stage Fase 13–14, tetapi jangan menjadikannya satu-satunya storage produksi sebelum adapter durable/WORM, autentikasi aktor, monitoring, dan restore/replay drill lulus.
16. Fondasi Fase 16 sudah tersedia; integrasikan repository WORM dan identity provider pada staging, lalu jalankan crash-recovery, concurrency, retention, backup, restore/replay, dan rollback rehearsal sebelum satu pun writer produksi diarahkan melalui gate.

## Deployment gates wajib

- Tidak ada mapping item ambigu atau lintas tenant.
- Retry dengan kunci sama tidak menambah ledger kedua.
- Saldo existing dan ledger baru sudah direkonsiliasi.
- Semua `openSession()`/`currentNativeSession()` milik implementasi baru ditutup pada `finally`; `currentSession()` tidak ditutup manual.
- Java tetap kompatibel 1.7 dan gaya Java 1.6.
- Admin dapat melihat menu, tetapi mutasi berisiko tetap melalui validasi, otorisasi aksi, dan audit.
- Ada rollback migration dan feature flag per writer sebelum canary.

## Status repository

- Perubahan adapter berada pada working copy SVN di bawah `C:\opt\AIS\ais\src\main`, tetapi masih lokal dan belum di-commit.
- Folder dokumentasi berada di repository Git `C:\opt\CodeBaseDesktopDanMobile`.
- Pada eksekusi ini belum dilakukan commit, push, build release, atau publikasi GitHub.
