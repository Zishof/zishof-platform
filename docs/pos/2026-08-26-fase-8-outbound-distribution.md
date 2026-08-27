# Fase 8 — Outbound dan Distribusi

## Outcome

Fondasi domain outbound sudah tersedia untuk reservasi, picking, packing, split shipment, Delivery Order, proof of delivery (POD), dan penerimaan outlet. Perubahan kuantitas tetap melewati ledger persediaan Fase 3; modul distribusi tidak membuat sumber saldo baru.

## Batas proses

- BAST vendor tetap menjadi bukti penerimaan dari pemasok pada alur procurement/inbound.
- Penerimaan outlet adalah dokumen distribusi internal dan tidak menggunakan ulang BAST vendor.
- Delivery Order adalah instruksi dan daftar muatan. Pengurangan stok gudang baru terjadi saat shipment benar-benar di-dispatch.
- POD mencatat perpindahan custody dan bukti serah, tetapi tidak menambah atau mengurangi stok.
- Stok outlet bertambah hanya sebesar kuantitas yang diterima (`acceptedQuantity`). Rusak dan ditolak dicatat sebagai discrepancy untuk tindak lanjut, bukan otomatis menjadi stok tersedia.

## Alur target

1. Permintaan outlet disetujui dan memiliki alokasi lot sumber.
2. `reserveApprovedOrder` membuat reservasi per alokasi.
3. Petugas menjalankan picking dan packing melalui transisi workflow.
4. Satu order dapat dipecah menjadi beberapa shipment; setiap shipment hanya memuat alokasi yang ditetapkan kepadanya.
5. `dispatchShipment` mengonsumsi reservasi dan mem-posting movement negatif pada lokasi sumber tepat satu kali.
6. Handover pengangkut dan perjalanan dicatat sebagai event workflow/custody.
7. POD disimpan sebagai bukti serah tanpa movement kuantitas.
8. `receiveAtOutlet` mem-posting movement positif di lokasi tujuan hanya untuk jumlah diterima.
9. Kekurangan, kerusakan, atau penolakan menghasilkan discrepancy yang harus diselesaikan melalui claim, retur, atau koreksi berotorisasi.

## Kontrak idempotensi

| Operasi | Kunci stabil |
|---|---|
| Reservasi | `OUTBOUND:{orderId}:{allocationId}:RESERVE` |
| Konsumsi reservasi | `OUTBOUND:{orderId}:{allocationId}:CONSUME` |
| Issue gudang | `OUTBOUND:{shipmentId}:{allocationId}:ISSUE` |
| Proof of delivery | `POD:{proofId}` |
| Penerimaan outlet | `OUTLET_RECEIPT:{receiptId}:{receiptLineId}:RECEIVE` |

Kunci tidak boleh dibuat dari timestamp retry. Adapter harus menyimpan dan mengunci kunci tersebut dalam transaksi yang sama dengan perubahan status dan ledger.

## Aturan split shipment dan custody

- Satu alokasi tidak boleh muncul dua kali pada shipment aktif yang berbeda.
- Total kuantitas shipment tidak boleh melebihi kuantitas yang sudah direservasi.
- Dispatch ulang dengan kunci sama harus menghasilkan `ALREADY_POSTED`/`ALREADY_APPLIED`, bukan movement kedua.
- Status minimum untuk dispatch adalah `PACKED`; order yang belum dipicking/dipacking ditolak.
- POD tidak menandakan penerimaan stok outlet. Receipt outlet tetap wajib agar custody dan saldo dapat direkonsiliasi.
- Receipt penuh mengubah order menjadi `RECEIVED`; receipt sebagian atau berselisih menjadi `PARTIALLY_RECEIVED` sampai penyelesaian.

## Artefak implementasi

- Agregat order dan baris: `OutboundOrder`, `OutboundLine`, `OutboundLotAllocation`.
- Shipment dan receipt: `Shipment`, `ProofOfDelivery`, `OutletReceipt`, `OutletReceiptLine`.
- Orkestrasi: `OutboundDistributionService`.
- Port workflow: `OutboundWorkflowPort`, `OutboundWorkflowCommand`, `OutboundWorkflowResult`.
- Hasil operasi: `OutboundOperationResult`.
- UAT executable: `OutboundDistributionServiceUat`.
- Draft DDL: `2026-08-26-fase-8-schema-outbound-distribution.sql`.

Kode authoritative berada di `C:\opt\AIS\ais\src\main\src` dan dicerminkan ke `C:\opt\AIS\ais\src\main\java`. Hasil kompilasi wajib diarahkan ke `C:\opt\AIS\ais\.codex-build`; dilarang menghasilkan `.class` di direktori source.

## Batas transaksi adapter

Service domain tidak membuka sesi Hibernate. Adapter runtime wajib menjalankan lock, reservasi/consume, posting ledger, penyimpanan event workflow, dan perubahan status dalam satu transaksi database. Jika satu alokasi gagal, seluruh operasi dokumen harus rollback. `openSession()` atau `currentNativeSession()` yang kelak dipakai adapter wajib ditutup pada `finally` dengan `clear`, `disconnect`, dan `close`; `currentSession()` tidak ditutup manual.

## Cakupan UAT kontrak

Eksekusi lokal pada 26 Agustus 2026 memakai `javac -source 1.7 -target 1.7` dengan output terisolasi di `C:\opt\AIS\ais\.codex-build\phase8-outbound`.

- Reservasi dan replay tidak menggandakan kuantitas.
- Picking dan packing mengikuti status yang sah.
- Split shipment A/B mengurangi stok sumber total tepat satu kali.
- Dispatch ulang tidak membuat issue atau consume reservasi kedua.
- POD dan replay POD tidak mengubah stok.
- Receipt penuh menambah stok outlet tepat sebesar jumlah diterima.
- Receipt parsial/rusak/ditolak hanya menambah accepted quantity dan menandai discrepancy.
- Dispatch dari status yang belum sah ditolak.

Hasil: `UAT Fase 8 lulus: reservasi, picking, packing, split shipment, POD, receipt, discrepancy, idempotensi.`

## Yang belum diaktifkan

- Draft DDL belum dijalankan pada database mana pun.
- Belum ada adapter Hibernate/JDBC, endpoint API, UI scanner picking/packing, integrasi pengangkut, atau penyimpanan foto/tanda tangan POD.
- Belum ada UAT PostgreSQL untuk row lock, konkurensi, atomic rollback, dan rekonsiliasi lintas lokasi.
- Belum ada migrasi data mutasi antar-outlet existing ke model distribusi baru.

## Gerbang staging

1. Review mapping tenant, gudang, outlet, item, UOM, lot, dan dokumen permintaan outlet.
2. Review serta jalankan draft DDL hanya di staging dengan backup dan rollback plan.
3. Implementasikan adapter transaksi dan unique constraint idempotensi.
4. Uji dua koneksi melakukan dispatch/receipt yang sama; hanya satu movement boleh tercipta.
5. Rekonsiliasi saldo sumber, in-transit, tujuan, rusak, dan ditolak pada split shipment.
6. Uji POD tanpa receipt, receipt tanpa POD sesuai kebijakan, partial receipt, over-receipt, dan claim.
7. Aktifkan feature flag per gudang/outlet setelah sign-off operasional dan akuntansi.

## Rollback

Sebelum runtime aktif, rollback cukup menonaktifkan feature flag dan menghapus draft data staging. Movement yang sudah terposting tidak boleh dihapus; pembatalan dilakukan dengan reversal ledger dan event workflow berotorisasi.

## Fase berikutnya

Fase 9 adalah Produksi: BOM/resep, production order, issue dan return bahan, penerimaan hasil, yield, scrap/waste, serta traceability lot bahan ke barang jadi.
