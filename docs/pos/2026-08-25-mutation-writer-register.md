# Register awal writer mutasi rantai pasok

Tanggal: 25 Agustus 2026  
Status: baseline awal; wajib diperdalam dengan audit query dan transaksi database

## Tujuan

Register ini menetapkan pemilik kode saat ini dan target ownership. Ia mencegah dua
modul menjadi writer independen untuk kejadian bisnis yang sama.

| Kejadian | Writer existing utama | Model/tabel existing | Target ownership | Strategi transisi |
|---|---|---|---|---|
| Simpan/ubah PR | `PengadaanPosApiHelper` | `PermintaanPengadaanMasterAsset*` | Procurement | Reuse + extension |
| Putusan PR | `PengadaanPosApiHelper` | `PermintaanPengadaanMasterAsset` | Procurement workflow | Pertahankan, tambah audit action granular |
| Simpan/ubah PO | `PengadaanPosApiHelper` | `PemesananPengadaanMasterAsset*` | Procurement | Reuse + extension |
| Putusan/back order PO | `PengadaanPosApiHelper` | `PemesananPengadaanMasterAsset*` | Procurement workflow | Pertahankan, idempotency wajib |
| Penerimaan vendor/BAST | `PengadaanPosApiHelper` | `PenerimaanPengadaanMasterAsset*` | Procurement receiving | BAST administratif tetap; receipt fisik menjadi aggregate baru |
| Sinkron BAST ke Kulakan | `PengadaanPosApiHelper` | BAST + `PengadaanProduk` | Adapter migrasi | Dual-read terkontrol; bukan writer final ledger |
| Pembelian langsung/Kulakan | `PosApi`/`KantinHelper` | `PengadaanFaktur`, `PengadaanProduk` | Direct procurement | Adapter ke receipt dan inventory movement |
| Terima tagihan vendor | `PengadaanPosApiHelper` | `SaldoAwalMasterAsset*` | Account Payable | Migrasi ke `ap_invoice*`; legacy retire-write |
| Pembayaran vendor | action Akuntansi/Keuangan | `ProsesTransfer`, `DaftarPengajuanTransfer` | Treasury/AP allocation | Reuse workflow + tabel alokasi invoice |
| Mutasi antar outlet | `PosApi`/`KantinHelper` | `MutasiStokToko` | Distribution | Adapter ke transfer/DO/shipment/receipt |
| Stok opname | `PosApi`/`KantinHelper` | `StokOpname` | Inventory Control | Emit tepat satu movement penyesuaian |
| Retur pembelian | `PosApi`/`KantinHelper` | `ReturPembelian` | Procurement/Inventory | Reference receipt/lot + reversal movement |
| Retur penjualan | `PosApi`/`KantinHelper` | `ReturPenjualan` | Sales/Inventory | Reference sale line + reversal movement |
| Penjualan POS | `PosApi`/`KantinHelper` | transaksi koperasi existing | Sales/POS | Local-first tetap; server emit movement idempoten |
| Produksi | action produksi existing | model produksi existing | Manufacturing | BOM/order/consume/output/waste harus terpisah |

## Pagar transaksi dan session

1. Setiap `openSession()` atau `currentNativeSession()` harus ditutup melalui
   `clear`, `disconnect`, dan `close` di `finally` sesuai kondisi session.
2. `currentSession()` tidak boleh ditutup manual.
3. Writer baru wajib mempunyai `idempotency_key`, `correlation_id`, actor, tenant,
   lokasi, dan waktu bisnis.
4. Satu kejadian stok hanya boleh menghasilkan satu `inventory_movement`.
5. Projection/cache stok tidak boleh menjadi writer balik ke ledger.

## Audit lanjutan yang belum selesai

- daftar seluruh SQL/HQL `insert`, `update`, dan `delete` pada domain terkait;
- batas transaksi setiap writer dan titik flush/commit;
- seluruh background scheduler yang dapat menulis stok atau jurnal;
- deteksi writer langsung ke saldo produk/batch;
- bukti rollback dan retry idempoten.

