# 76. Pre-flight `enforce` Proteksi SQL — Go/No-Go

Tanggal: 2 September 2026  
Lanjutan: dok. 70–72 (penjaga SQL), dok. 75 (audit endpoint selesai)  
Sifat: verifikasi kesiapan sebelum menaikkan `mode_proteksi_sql_endpoint` ke
`enforce`

## Pertanyaan yang dijawab

Mode `log` sudah menyala di UAT. Sebelum naik ke `enforce`, satu risiko harus
ditutup: **apakah ada kueri SAH dari halaman yang justru akan ditolak penjaga**
saat `enforce`? Bila ada, halaman itu patah begitu mode dinaikkan. Jawabannya
dicari dengan menyisir SELURUH SQL klien di basis kode, bukan menebak.

## Yang ditolak penjaga saat `enforce`

- `action=sql` (baca): wajib diawali `SELECT`/`WITH`/`EXPLAIN`/`(`, satu
  statement (tanpa `;` di tengah), tanpa kata kunci tulis/DDL
  (`insert/update/delete/drop/alter/truncate/create/grant/revoke/merge/call/`
  `copy/vacuum/reindex/cluster/into`), tanpa objek sistem, tanpa kolom kredensial.
- `action=update_data` (tulis): DML boleh (termasuk statement bertumpuk), tetapi
  DDL/berbahaya (`drop/alter/truncate/create/grant/revoke/vacuum/reindex/`
  `cluster/copy`) dan objek sistem ditolak.

Catatan penting: pencocokan kata kunci memakai batas kata dan `_` termasuk
karakter kata, sehingga kolom seperti `create_date`, `update_time`,
`insert_by` **tidak** memicu penolakan — hanya kata telanjang.

## Hasil sisir seluruh JSP

| Pemeriksaan | Temuan |
| --- | --- |
| `action=sql` tidak diawali SELECT/WITH | **0** |
| `action=sql` dengan `;` di tengah (stacked) | **0** |
| SELECT memuat kata tulis/DDL telanjang (`into/call/copy/merge/cluster/…`) | **0** |
| `action=sql` menyentuh objek sistem (`pg_*`, `information_schema`) | **0** |
| `action=sql` menyentuh kolom kredensial | **0** (dok. 72) |
| `action=update_data` memuat DDL telanjang | **0** |

Temuan yang sempat mencurigakan — `UPDATE koperasi.pembelian SET terlayani …` —
diperiksa dan ternyata seluruhnya dikirim dengan `action=update_data` (bukan
`action=sql`), sehingga sah di mode `enforce`.

## Kesimpulan: GO

Menaikkan `enforce` **tidak akan mematahkan** halaman mana pun pada kode saat
ini. Dua lapis dasar (tulis anonim ditutup, kolom kredensial diblokir) sudah
aktif tanpa bergantung mode; `enforce` menambahkan penolakan read-only dan
anti-DDL untuk jalur yang tersisa.

## Cara mengulang pemeriksaan (mis. sebelum enforce di produksi)

Dijalankan dari akar `webapp`:

```bash
# 1) action=sql yang tidak diawali SELECT/WITH (harus kosong)
grep -rhoE "sql: *[\"'\`][^\"'\`]{0,40}" --include=*.jsp . \
  | grep -viE "sql: *[\"'\`] *(select|with|explain|\()" | grep -iE "sql:"

# 2) titik-koma di tengah string SQL (harus kosong)
grep -rhoE "sql *[:=] *[\"'\`][^\"'\`;]*;[^\"'\`]+[\"'\`]" --include=*.jsp .

# 3) objek sistem pada SQL klien (harus kosong / hanya di halaman non-sql)
grep -rloiE "information_schema|pg_catalog|pg_shadow|pg_authid" --include=*.jsp .
```

Bila ketiganya kosong seperti saat dokumen ini ditulis, `enforce` aman
dinyalakan. Bila kelak ada halaman baru yang gagal salah satu pemeriksaan,
perbaiki halaman itu (ubah ke `action=update_data` untuk tulis, atau susun ulang
kuerinya) sebelum menaikkan mode — atau biarkan `log` dan amati.

## Batas verifikasi ini

Pemeriksaan bersifat **statis** atas SQL yang tertulis di halaman. Ia tidak
menangkap SQL yang dirakit sepenuhnya dari nilai runtime yang tak terlihat di
sumber. Karena itu urutan `log → amati → enforce` tetap dianjurkan: mode `log`
akan mencatat penolakan nyata (`[SqlSecurityGuard]`) tanpa memutus apa pun,
memberi bukti lapangan sebelum `enforce`.

## Status

- UAT: `mode_proteksi_sql_endpoint = log` (aktif).
- Kesiapan `enforce`: **GO** menurut pemeriksaan statis.
- Menaikkan UAT/produksi ke `enforce` = keputusan operasional pemilik; belum
  dilakukan.
