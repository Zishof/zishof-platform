# 63. Merapikan Master UOM per Kategori

Tanggal: 1 September 2026  
Status: diterapkan dan diverifikasi pada basis data UAT lokal
(`127.0.0.1:5432/ais`); prosedur untuk lingkungan lain tersedia di bawah  
Rujukan: dok. 56 (persiapan operasional), dok. 52/59/61 (mesin konversi UOM)

## Mengapa ini mendesak

Mesin konversi menegakkan kesekategorian di SATU titik
(`KantinHelper.faktorUomInputKeDasar`, dipakai kasir satuan jual, Pack,
kulakan, PR/PO/BAST, dan pratinjau klien `UomKonversi`). Titik itu menolak
konversi bila kategori salah satu satuan **kosong** — bukan hanya bila
kategorinya berbeda.

Audit master UOM menemukan kondisi yang membuat SELURUH fitur ber-UOM mati:

| Temuan | Jumlah |
| --- | --- |
| Baris master UOM seluruhnya | **1** (`PCS`) |
| Baris itu: kategori / tipe konversi / rasio | semuanya **NULL** |
| Kategori dengan satuan acuan (REFERENCE) | **0** |
| Produk aktif memakai `PCS` sebagai satuan dasar | 2 |
| Produk aktif **tanpa** satuan dasar sama sekali | 8.674 |

Akibatnya setiap penjualan per satuan besar, Pack, atau kulakan ber-UOM
ditolak dengan pesan "Perbaiki kategori UOM pada Master Data > Satuan/UOM".

## Aturan baku yang ditegakkan

1. Setiap satuan **wajib** punya kategori (`UNIT`, `BERAT`, `VOLUME`,
   `PANJANG`, atau kategori lain yang dipakai konsisten).
2. Setiap kategori punya **tepat satu** satuan acuan: `tipe_konversi =
   REFERENCE` dengan `rasio = 1`.
3. Satuan lain memakai `BIGGER` (rasio = berapa acuan per satuan itu, mis.
   Kilogram 1000 terhadap Gram) atau `SMALLER` (rasio = berapa satuan itu
   per acuan, mis. Miligram 1000).
4. `rasio` selalu > 0; nama satuan unik (case-insensitive).
5. Produk tidak boleh memakai satuan pembelian / satuan pack yang berbeda
   kategori dengan satuan dasarnya (sudah ditolak server sejak dok. 61).

## Yang diterapkan

- Baris `PCS` diperbaiki menjadi `UNIT / REFERENCE / 1` — kolom yang diisi
  hanya yang sebelumnya kosong, nama dan id tidak diubah sehingga dua produk
  yang memakainya tetap utuh.
- Ditambahkan 17 satuan standar (idempoten — nama yang sudah ada dilewati):

| Kategori | Acuan | Turunan |
| --- | --- | --- |
| UNIT | Pcs | Lusin 12, Gross 144, Pasang 2 |
| BERAT | Gram | Miligram (SMALLER 1000), Ons 100, Kilogram 1000, Kuintal 100.000, Ton 1.000.000 |
| VOLUME | Mililiter | Sentiliter 10, Liter 1.000, Kiloliter 1.000.000 |
| PANJANG | Sentimeter | Milimeter (SMALLER 10), Meter 100, Kilometer 100.000 |

**Sengaja TIDAK diseed**: kemasan ber-isi khusus (Dus, Karung, Pak, Renceng).
Isinya berbeda per produk — "Dus" bisa 6 botol pada satu produk dan 24 pada
produk lain — sedangkan rasio tersimpan di master UOM yang berlaku global.
Kemasan seperti itu dibuat pemilik sebagai satuan tersendiri dengan isi pada
namanya (mis. **Dus 6**, **Karung 50**) lalu dipakai sebagai UOM Pack atau
ambang aturan grosir.

## Bukti

Verifikasi struktur sesudah perapian (satuan aktif):

| kategori | satuan | acuan | rasio tidak sah |
| --- | --- | --- | --- |
| BERAT | 6 | 1 | 0 |
| PANJANG | 4 | 1 | 0 |
| UNIT | 4 | 1 | 0 |
| VOLUME | 4 | 1 | 0 |

Verifikasi fungsional `TesUomRapi` — memanggil fungsi yang PERSIS dipakai
kasir/kulakan: **9/9** — Pcs→Pcs = 1 (sebelumnya selalu ditolak), Lusin 12,
Gross 144, Kilogram 1000, Ons 100, Ton 1.000.000, Miligram 0,001, sedangkan
VOLUME→BERAT dan PANJANG→UNIT tetap ditolak dengan pesan terbaca.

## Prosedur untuk lingkungan lain (mis. produksi)

Jalankan audit dulu, terapkan setelah hasilnya dibaca, lalu verifikasi.
Seluruh perintah idempoten dan tidak menyentuh baris milik pemilik selain
mengisi kolom yang kosong/tidak sah.

```sql
-- 1) AUDIT: baris tidak sah dan kategori tanpa acuan.
SELECT id, nama, kategori, tipe_konversi, rasio FROM koperasi.satuan_produk
 WHERE kategori IS NULL OR TRIM(kategori) = '' OR tipe_konversi IS NULL
    OR TRIM(tipe_konversi) = '' OR rasio IS NULL OR rasio <= 0;

SELECT COALESCE(NULLIF(TRIM(kategori), ''), '(KOSONG)') AS kategori,
       COUNT(*) FILTER (WHERE UPPER(COALESCE(tipe_konversi, '')) = 'REFERENCE') AS acuan
  FROM koperasi.satuan_produk WHERE COALESCE(aktif, true)
 GROUP BY 1 HAVING COUNT(*) FILTER (WHERE UPPER(COALESCE(tipe_konversi, '')) = 'REFERENCE') <> 1;

-- 2) PERBAIKI nama satuan yang padanannya pasti (hanya kolom kosong/tak sah).
UPDATE koperasi.satuan_produk
   SET kategori = COALESCE(NULLIF(TRIM(kategori), ''), 'UNIT'),
       tipe_konversi = COALESCE(NULLIF(TRIM(tipe_konversi), ''), 'REFERENCE'),
       rasio = CASE WHEN rasio IS NULL OR rasio <= 0 THEN 1 ELSE rasio END
 WHERE LOWER(TRIM(nama)) IN ('pcs', 'pc', 'buah', 'unit');

-- 3) SEED satuan standar (lewati nama yang sudah ada).
INSERT INTO koperasi.satuan_produk (nama, aktif, kategori, tipe_konversi, rasio)
SELECT v.nama, true, v.kategori, v.tipe, v.rasio
  FROM (VALUES
        ('Pcs','UNIT','REFERENCE',1), ('Lusin','UNIT','BIGGER',12),
        ('Gross','UNIT','BIGGER',144), ('Pasang','UNIT','BIGGER',2),
        ('Gram','BERAT','REFERENCE',1), ('Miligram','BERAT','SMALLER',1000),
        ('Ons','BERAT','BIGGER',100), ('Kilogram','BERAT','BIGGER',1000),
        ('Kuintal','BERAT','BIGGER',100000), ('Ton','BERAT','BIGGER',1000000),
        ('Mililiter','VOLUME','REFERENCE',1), ('Sentiliter','VOLUME','BIGGER',10),
        ('Liter','VOLUME','BIGGER',1000), ('Kiloliter','VOLUME','BIGGER',1000000),
        ('Sentimeter','PANJANG','REFERENCE',1), ('Milimeter','PANJANG','SMALLER',10),
        ('Meter','PANJANG','BIGGER',100), ('Kilometer','PANJANG','BIGGER',100000)
       ) AS v(nama, kategori, tipe, rasio)
 WHERE NOT EXISTS (SELECT 1 FROM koperasi.satuan_produk u
                    WHERE LOWER(TRIM(u.nama)) = LOWER(v.nama));

-- 4) VERIFIKASI: tiap kategori tepat 1 acuan, tanpa rasio tidak sah.
SELECT COALESCE(NULLIF(TRIM(kategori), ''), '(KOSONG)') AS kategori, COUNT(*) AS satuan,
       COUNT(*) FILTER (WHERE UPPER(COALESCE(tipe_konversi, '')) = 'REFERENCE') AS acuan,
       COUNT(*) FILTER (WHERE rasio IS NULL OR rasio <= 0) AS rasio_tidak_sah
  FROM koperasi.satuan_produk WHERE COALESCE(aktif, true) GROUP BY 1 ORDER BY 1;
```

Ini DML (data master), bukan DDL — kebijakan "skema hanya lewat Hibernate"
(dok. 58) tetap utuh. Ambil cadangan basis data sebelum langkah 2 dan 3 di
lingkungan produksi.

## Keputusan pemilik: satuan dasar Pcs massal (1 September 2026)

Audit di atas menyisakan **8.674 produk aktif tanpa satuan dasar**, yang
membuat fitur satuan jual, Pack, dan ambang grosir per satuan tidak dapat
dipakai pada produk tersebut. Pemilik memilih **opsi 1**: tetapkan **Pcs**
sebagai satuan dasar untuk seluruh produk yang belum ber-UOM.

Yang dijalankan (mode audit dulu, baru terapkan):

```sql
-- Hanya baris yang BELUM punya satuan; produk yang sudah ber-UOM tidak disentuh.
UPDATE koperasi.produk
   SET satuan = (SELECT id FROM koperasi.satuan_produk
                  WHERE LOWER(TRIM(nama)) = 'pcs' AND COALESCE(aktif, true)
                  ORDER BY id LIMIT 1)
 WHERE satuan IS NULL;
```

Hasil di basis data UAT:

| Pemeriksaan | Sebelum | Sesudah |
| --- | --- | --- |
| Produk tanpa satuan dasar | 8.674 | **0** |
| Produk bersatuan Pcs | 3 | 8.677 |
| Produk bersatuan selain Pcs (tidak disentuh) | 1 | 1 |
| Produk menunjuk satuan tidak sah (kategori/rasio kosong) | — | **0** |
| Satuan pembelian beda kategori dgn satuan dasar | — | **0** |

`satuan_pembelian` sengaja dibiarkan kosong: mesin konversi memakai satuan
dasar sebagai acuan bila satuan pembelian belum diisi, sehingga kulakan per
Pcs tetap benar tanpa menebak kemasan pemasok tiap produk.

### Cara membalik

Seluruh 8.674 id yang diubah dicatat lebih dulu ke berkas jejak
(`jejak-satuan-null.csv`, kolom `id,kode`) sebelum satu baris pun ditulis,
sehingga perubahan dapat dibatalkan penuh:

```sql
UPDATE koperasi.produk SET satuan = NULL WHERE id IN (/* id dari berkas jejak */);
```

Tanpa berkas jejak, pembalikan massal tidak lagi dapat membedakan produk yang
tadinya kosong dari produk yang memang bersatuan Pcs — simpan berkas itu
selama masa pemantauan bila prosedur ini dijalankan di produksi.

### Produk curah — diperiksa, ternyata tidak ada

Kekhawatiran pada opsi 1 adalah barang curah (beras/gula/minyak kiloan) yang
seharusnya bersatuan Kilogram/Liter, bukan Pcs. Penyaringan nama menemukan 89
kandidat, dan sesudah dibaca satu per satu:

- **82** adalah jasa laundry demo ("Cuci Gorden Reguler 3 Hari Per Kg") —
  bukan barang stok;
- **7** sisanya justru barang **kemasan**: "Beras bengawan koi 5kg", "Gula
  Pasir 1kg", "Telur Garuda 250gr". Satu bungkus = satu Pcs, jadi Pcs benar.

Tidak ada produk yang perlu dikoreksi menjadi Kilogram/Liter di katalog ini.
Bila kelak ditambahkan barang timbangan, ubah satuan dasarnya lewat Master
Data > Produk — mengubah satu produk tidak memengaruhi produk lain.

## Catatan pilihan yang tidak diambil

Dua pilihan lain tetap tercatat bila kondisi berubah: mengisi satuan lewat
impor Excel katalog (kolom "Satuan"), atau membiarkan kosong — penjualan biasa
tetap berjalan, hanya fitur ber-UOM yang tidak dapat dipakai pada produk itu.
