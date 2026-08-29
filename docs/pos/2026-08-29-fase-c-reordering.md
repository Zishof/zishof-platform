# Fase C — Reordering Lengkap (Min-Max + Rute Beli/Produksi)

Tanggal: 29 Agustus 2026  
Status: server + Flutter **lulus** (TesFaseCReorder 19/19 di DB UAT; Flutter
501/501; analyze bersih di berkas tersentuh); belum di-commit  
Rujukan: SVN `docs/pos/53-fase-c-reordering-lengkap.md` (keputusan lengkap +
koreksi peta + bug laten), dok. 48 §4 Fase 3

## Ringkas

Penjadwal ambang stok (`StokThresholdScheduler`, tiap 4 jam) kini lengkap:

- **Min-max**: `AmbangStokGudang.maxQty` baru — saran qty = target − stok;
  kosong = perilaku lama (2× ambang). Disunting di layar ZK Ambang Stok
  (kolom "Target Maks" baru).
- **Pembulatan kemasan**: saran dibulatkan NAIK ke Satuan Pembelian produk
  lewat `faktorUomInputKeDasar` yang SAMA dengan kasir/kulakan (butuh 70 kg,
  karung 50 → 2 karung = 100). Konfigurasi UOM salah tidak menggagalkan
  siklus — keterangan pengajuan menjelaskan masalahnya.
- **Rute pemenuhan**: `Produk.rute` baru — kosong/BELI = pengajuan pembelian
  (mesin lama); PRODUKSI = **draf Work Order** (status DRAFT, merujuk BOM
  aktif bila ada, catatan jujur bila belum ada BOM). Idempoten dua-duanya.

## Bug laten yang terungkap harness

Kueri penerima notifikasi memakai `select id from public.tbmuser` — PK
tbmuser adalah **userid** (String). PSQLException-nya ditangkap, tetapi
transaksi PostgreSQL telanjur batal server-side → commit siklus ikut gagal →
**pengajuan otomatis tidak pernah tersimpan sejak fitur ambang lahir**.
Diperbaiki: kueri ke `userid` + notifikasi pindah ke sesi terpisah supaya
kegagalan apa pun di sana tidak lagi meracuni transaksi ledger.

## Sisi kasir (repo ini)

- `models.dart`: `Produk.rute` ('' = BELI bawaan; katalog lama tanpa field
  tetap terbaca kosong).
- `produk_screen.dart`: SegmentedButton "Rute Pemenuhan Ulang Stok"
  (Beli (bawaan) / Produksi Sendiri) di bawah Jenis Item; payload
  `produk_simpan` membawa `rute` (null saat kosong); baris optimistis ikut.
- `test/rute_produk_kontrak_test.dart` (baru, 2 uji): kompatibilitas katalog
  lama dan pemetaan nilai server.

Server: `produk_simpan` memvalidasi rute (BELI/PRODUKSI/null, selain itu
status 91); `katalog` mengirim `rute`.

## Bukti

- `TesFaseCReorder` 19/19 (DB UAT, refleksi ke `prosesSatuAmbang` persis yang
  dipanggil siklus; sengaja tidak memanggil `jalankanSekali()` supaya ambang
  asli DB UAT tidak ikut tersapu).
- `javac 1.7` EXIT=0 semua berkas server; 0 `.class` di pohon sumber.
- Flutter suite penuh **501 lulus / 0 gagal**; analyze bersih di ketiga
  berkas tersentuh.
