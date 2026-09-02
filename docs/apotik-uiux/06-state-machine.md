# 06 — State Machine

Mengganti kumpulan boolean yang bisa saling bertentangan.

## Transaksi POS

`idle → creating → open → (held) → (approvalRequired) → readyToPay → paymentPending → paid | paidUnsynced | paymentFailed`
lalu `voidRequested → voided`, atau `returned`.

Aturan yang WAJIB ditegakkan UI:
- `paymentPending`: SELURUH tombol bayar dikunci (cegah double-submit);
- retry memakai **idempotency key yang sama** (perilaku existing dipertahankan);
- `paidUnsynced` ≠ `paid` — jangan tampilkan sebagai sukses server;
  sejak Fase 6 status ini BENAR-BENAR dipakai: `ApiException.offline` pada
  `apotik_bayar` membawanya ke sini (bukan `paymentFailed`), keranjang
  dipertahankan, dan payload-nya diantre di
  `ApotikPembayaranTertundaStore` untuk dipastikan lewat kiriman ulang
  ber-kode sama;
- gagal cetak TIDAK membatalkan transaksi yang sudah dibukukan;
- pindah layar saat proses berjalan → konfirmasi.

## Resep

`waitingReview → underReview → (onHoldForClarification) → approved | approvedWithNote | rejected`
→ `preparing → awaitingDoubleCheck → readyForCounseling → readyForPickup → dispensed`, atau `cancelled`.

Status yang belum punya aksi server ditampilkan **read-only** (tidak ada tombol
yang tidak menulis apa pun) — lihat IR-04/IR-05.

## Batch

`eligible | nearExpiry | held | quarantine | recall | damaged | expired | depleted`

Server saat ini hanya menyediakan `kedaluwarsa` + `stok`, sehingga UI menurunkan:
`expired` (tanggal lewat), `nearExpiry` (ambang), `depleted` (stok 0), `eligible` (sisanya).
Status `held/quarantine/recall/damaged` **tidak dikarang** — menunggu IR-02.
