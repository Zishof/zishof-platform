# ADR: kontrak data terpadu rantai pasok eBisnis

Tanggal keputusan: 25 Agustus 2026  
Status: **diterima sebagai dasar desain; implementasi bertahap**

## Konteks

Pengadaan, stok, distribusi, produksi, POS, tagihan, pembayaran, dan jurnal saat ini
telah mempunyai model matang tetapi belum memakai satu kontrak identitas, waktu,
lokasi, idempotency, dan audit. Penambahan Pergudangan tidak boleh membuat sumber
kebenaran kedua.

## Keputusan

### Identitas dan business key

- Primary key database boleh mengikuti strategi existing selama migrasi.
- Dokumen baru wajib memiliki business key stabil yang unik dalam tenant.
- Integrasi dan retry memakai `idempotency_key`, bukan nomor urut tampilan.
- `correlation_id` mengikat alur stock request → PR/PO → receipt → shipment → outlet.

### Tenant dan lokasi

- Semua aggregate operasional baru wajib mempunyai tenant scope eksplisit.
- Gudang, toko/outlet, zone, bin, dock, dan carrier mempunyai identitas stabil.
- Otorisasi `VIEW_ALL_LOCATION` dipisahkan dari izin melihat menu.

### Waktu

- Waktu bisnis disimpan sebagai instant/timestamp yang tidak ambigu.
- Zona tampilan mengikuti timezone tenant; default operasional saat ini
  `Asia/Jakarta`.
- `created_at`, `updated_at`, `business_at`, dan `posted_at` tidak boleh dipakai
  bergantian karena memiliki arti berbeda.

### Presisi

- Nilai uang disimpan dalam presisi database yang disetujui domain akuntansi; tidak
  memakai floating point untuk canonical money.
- Quantity mempunyai presisi dan UOM eksplisit.
- Konversi UOM disimpan sebagai rasio terkontrol dan snapshot dokumen menjaga nilai
  historis.

### Stok

- `inventory_movement` adalah ledger immutable canonical.
- Saldo produk/batch/bin adalah projection yang dapat dibangun ulang.
- Koreksi dilakukan dengan movement lawan, bukan mengubah event historis.
- Permintaan stok outlet bukan PR vendor; penerimaan outlet bukan BAST vendor.

### Tagihan dan pembayaran

- `SaldoAwalMasterAsset` tidak menjadi canonical invoice baru.
- Invoice, invoice line, matching, dispute, allocation, payment, dan posting
  mempunyai lifecycle terpisah.
- `ProsesTransfer` dan `DaftarPengajuanTransfer` tetap digunakan sebagai workflow
  transfer existing melalui extension/alokasi.

### Hak akses

- `TbmroleAction`/JSON role existing tetap sumber izin selama transisi.
- Kunci kanonik dan alias diterjemahkan oleh registry, bukan disimpan sebagai dua
  kewenangan.
- Admin melihat semua menu, tetapi approve/post/reverse/cancel tetap divalidasi dan
  diaudit.

### Kompatibilitas dan partisi

- Route legacy dipertahankan melalui alias/adaptor sampai telemetry membuktikan aman
  untuk dihentikan.
- Tidak dibuat tabel transaksi per hari.
- Partisi bulanan hanya setelah benchmark, query memakai partition key, dan prosedur
  maintenance/restore tersedia.

## Konsekuensi

Desain membutuhkan extension dan adapter tambahan, tetapi menghindari migrasi besar
sekali jalan. Read model dapat dibangun paralel, sedangkan writer canonical hanya
dipindahkan setelah rekonsiliasi dan rollback terbukti.

## Pagar sebelum DDL produksi

1. snapshot schema dan constraint;
2. audit duplicate/orphan/null ratio;
3. golden dataset beserta checksum;
4. backup dan restore ke target terisolasi;
5. migration idempoten dan rollback plan;
6. approval pemilik domain serta DBA.

