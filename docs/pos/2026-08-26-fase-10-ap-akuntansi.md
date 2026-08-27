# Fase 10 — Accounts Payable dan Akuntansi

Tanggal: 26 Agustus 2026

## Outcome

Fondasi domain Fase 10 telah dibuat untuk memisahkan invoice vendor kanonis dari penyalahgunaan tabel saldo awal, mengikat invoice dengan PO dan penerimaan melalui three-way match, mengalokasikan pembayaran legacy secara idempoten, serta mem-posting dan membalik jurnal tanpa menghapus histori. Implementasi ini masih berupa kontrak domain dan draft skema; belum mengubah database atau writer produksi.

## Keputusan arsitektur

- `SaldoAwalMasterAsset` tidak lagi menjadi target writer invoice vendor baru. Data existing hanya menjadi sumber bridge/migrasi dan shadow-read selama cutover.
- `PemesananPengadaanMasterAsset` tetap menjadi sumber PO dan `PenerimaanPengadaanMasterAsset` tetap menjadi sumber BAST/penerimaan untuk pencocokan.
- `ProsesTransfer` dan `DaftarPengajuanTransfer` tetap dipakai sebagai eksekutor pembayaran existing. Tabel `ap_payment_allocation` menambahkan hubungan eksplisit pembayaran ke invoice.
- Posting jurnal memiliki identitas `(tenant, sourceType, sourceId, eventType)` dan idempotency key. Retry tidak membuat jurnal ganda.
- Koreksi jurnal dilakukan melalui reversal baru dengan nilai lawan. Jurnal lama tidak dihapus.
- Period lock diperiksa sebelum posting atau reversal.

## Alur kanonis

1. Invoice vendor diregistrasi dengan nomor unik per tenant dan vendor.
2. Setiap baris dicocokkan dengan detail PO dan detail penerimaan/BAST.
3. Selisih atau referensi yang tidak lengkap menjadi `MATCH_EXCEPTION`, bukan dipaksa lolos.
4. Invoice `MATCHED` dapat disetujui dan dibuatkan jadwal jatuh tempo/termin.
5. Pengajuan dan pelaksanaan transfer tetap berjalan melalui modul keuangan existing.
6. Pembayaran dialokasikan ke satu atau beberapa invoice dengan idempotency key.
7. Credit note mengurangi saldo terbuka tanpa mengubah histori invoice.
8. Invoice, pembayaran, dan reversal diposting melalui `JournalPostingPort`.
9. Subledger AP direkonsiliasi dengan GL sebelum period close dan sebelum cutover.

## Artefak kode

Package `ais.common.inventory.accountspayable` berisi:

- `VendorInvoice` dan `VendorInvoiceLine` untuk aggregate invoice.
- `ThreeWayMatchResult` untuk hasil pencocokan PO–receipt–invoice.
- `PaymentAllocation` untuk bridge ke `ProsesTransfer`/`DaftarPengajuanTransfer`.
- `CreditNote` untuk koreksi saldo terbuka.
- `AccountsPayableStatus` untuk state machine invoice.
- `AccountsPayablePort`, `JournalPostingPort`, dan `PeriodLockPort` sebagai batas adapter.
- `AccountsPayableService` untuk registrasi, matching, approval, pembayaran, credit note, posting, dan reversal.

Source kanonis berada di `C:\opt\AIS\ais\src\main\src\ais\common\inventory\accountspayable` dan mirror kompatibilitas berada di `C:\opt\AIS\ais\src\main\java\ais\common\inventory\accountspayable`.

## Draft skema

Draft `2026-08-26-fase-10-schema-ap-akuntansi.sql` mencakup:

- invoice, line, match result/line, dispute, dan payment schedule;
- credit note dan payment allocation;
- posting source, posting job, dan reversal;
- valuation layer persediaan dan period lock;
- event audit AP dan indeks operasional.

Draft bersifat repeatable melalui `IF NOT EXISTS`, tetapi tetap wajib direview DBA. Tidak ada DDL/DML yang dijalankan pada fase ini.

## UAT yang lulus

`AccountsPayableServiceUat` dikompilasi dengan Java 1.7 pada direktori output terisolasi dan lulus **26 assertion**, mencakup:

- penolakan nomor invoice vendor duplikat;
- invoice tanpa PO/BAST menjadi exception;
- exact three-way match dan approval;
- pembayaran parsial, pelunasan, serta penolakan overpayment;
- retry pembayaran dan credit note yang idempoten;
- credit note mengurangi saldo terbuka;
- posting invoice dan pembayaran;
- posting sumber yang sama tidak menggandakan jurnal;
- reversal menambah jurnal lawan tanpa menghapus jurnal lama;
- period lock menolak posting;
- subledger terbuka sama dengan saldo aggregate invoice yang eligible.

## Gerbang implementasi runtime

1. Review pemetaan vendor, PO detail, receipt detail, transfer, dan jurnal pada database staging.
2. Jalankan draft DDL hanya setelah backup, rollback script, dan persetujuan DBA tersedia.
3. Buat adapter Hibernate/JDBC dengan transaksi atomik. Jika memakai `openSession()` atau `currentNativeSession()`, lakukan `clear/disconnect/close` pada `finally`; `currentSession()` tidak ditutup manual.
4. Aktifkan shadow-read dari data legacy dan buktikan saldo invoice, pembayaran, credit note, AP subledger, serta GL sama.
5. Uji dua koneksi untuk nomor invoice, payment allocation, dan posting key yang sama.
6. Pilot satu tenant/vendor dengan feature flag default OFF.
7. Setelah minimal satu periode rekonsiliasi disetujui, hentikan writer invoice vendor ke `SaldoAwalMasterAsset` dan pertahankan reader selama masa transisi.

## Rollback

- Matikan feature flag writer AP baru.
- Kembalikan pembacaan ke sumber legacy tanpa menghapus tabel atau data AP baru.
- Jangan menghapus jurnal; buat reversal bila posting bisnis harus dibatalkan.
- Simpan hasil rekonsiliasi dan audit idempotency untuk investigasi.

## Status

Fondasi kode dan UAT domain selesai. Adapter database, migrasi staging, UI lintas platform, dan aktivasi writer belum dilakukan dan menjadi pekerjaan fase runtime berikutnya.
