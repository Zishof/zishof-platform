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

### Dijalankan otomatis saat boot -- tidak ada SQL manual lagi

`AppStartupListener` memanggil tiga langkah idempoten di `InitIndex`, sehingga
lingkungan baru (termasuk ebisnis.id) cukup memasang build terbaru dan
me-restart Tomcat; SQL di atas tinggal menjadi rujukan, bukan prosedur.

| Langkah | Method | Kapan berjalan |
| --- | --- | --- |
| Rapikan master UOM | `initMasterUomStandar()` | setiap boot (idempoten) |
| Pembalikan | `initBalikkanSatuanPcsMassal()` | hanya bila saklar diaktifkan |
| Isi satuan dasar Pcs | `initSatuanDasarPcsMassal()` | sekali per lingkungan |

Urutan itu wajib: master UOM harus sah sebelum satuan dasar menunjuk kepadanya,
dan pembalikan harus berjalan sebelum pengisian supaya hasilnya tidak langsung
diisi ulang pada boot yang sama.

Penjaga yang melekat pada langkah-langkah itu:

- Pengisian mencatat setiap id ke `koperasi.jejak_satuan_pcs` **sebelum**
  mengubah satu baris pun.
- Pengisian berjalan **sekali** per lingkungan, ditandai konfigurasi
  `kantin_uom_isi_pcs_massal_selesai`. Produk baru wajib memilih satuan di layar
  Produk, jadi pengisian diam-diam pada tiap restart tidak diperlukan dan hanya
  menyulitkan penelusuran.
- Pengisian menolak menunjuk baris Pcs yang sendirinya belum sah (kategori atau
  rasio kosong) -- menunjuk satuan rusak hanya memindahkan kegagalan ke kasir.
- Ketiganya membaca konfigurasi lewat SQL langsung, **bukan**
  `Common.bolehKonfigurasi`. Lapisan `KonfigurasiManager` belum tentu siap sedini
  itu pada urutan boot; di luar container pemanggilannya terbukti menggantung,
  dan init lain di kelas yang sama juga murni SQL.

Bukti perilaku: harness `TesInitUom` memanggil ketiga method lewat refleksi --
persis yang dipanggil saat boot -- terhadap basis data UAT: **12/12 lulus**,
termasuk "boot berikutnya tidak mengisi produk baru", "produk yang dikoreksi
manual ke Kilogram tidak ikut dikosongkan", dan "saklar mematikan dirinya
sendiri".

### Cara membalik

Cukup satu baris konfigurasi -- tidak perlu lagi menulis SQL berisi ribuan id:

```sql
-- Aktifkan saklar, lalu restart Tomcat. Saklar mematikan dirinya sendiri.
UPDATE public.konfigurasi SET nilai = 'aktif'
 WHERE nama = 'kantin_uom_balikkan_pcs_massal';
-- (bila barisnya belum ada)
INSERT INTO public.konfigurasi (nama, nilai)
SELECT 'kantin_uom_balikkan_pcs_massal', 'aktif'
 WHERE NOT EXISTS (SELECT 1 FROM public.konfigurasi
                    WHERE nama = 'kantin_uom_balikkan_pcs_massal');
```

Pada boot berikutnya `initBalikkanSatuanPcsMassal()` mengosongkan satuan **hanya**
produk yang tercatat di `koperasi.jejak_satuan_pcs` **dan** masih bersatuan Pcs,
lalu mematikan saklar sendiri dan menandai pengisian selesai supaya tidak diisi
ulang. Syarat "masih bersatuan Pcs" itu wajib: tanpanya, produk yang sesudah
pengisian dikoreksi manual (mis. menjadi Kilogram) ikut dikosongkan dan koreksi
pemilik hilang.

Isi tabel jejak di basis data UAT: **8.674 id**, diimpor dari berkas jejak yang
dibuat saat pengisian pertama kali dijalankan. Berkas itu tetap disimpan sebagai
cadangan di luar basis data:

    docs/pos/jejak/2026-09-01-produk-tanpa-satuan-sebelum-pcs-massal.csv
    kolom: id,kode   |   8.674 baris data   |   174 KB
    SHA-256: 4d7b298340009072b3c4a641081ac8950fb92500d49a6636d672aa5124cb4718

Bentuk manualnya -- bila perlu dijalankan tanpa restart -- tetap sama:

```sql
UPDATE koperasi.produk
   SET satuan = NULL
 WHERE id IN (SELECT j.produk FROM koperasi.jejak_satuan_pcs j)
   AND satuan = (SELECT id FROM koperasi.satuan_produk
                  WHERE LOWER(TRIM(nama)) = 'pcs' AND COALESCE(aktif, true)
                  ORDER BY id LIMIT 1);
```

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
