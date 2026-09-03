# 82. UAT: Proteksi Endpoint SQL Dinaikkan ke `enforce`

Tanggal: 3 September 2026  
Lingkungan: **UAT lokal** (`127.0.0.1:5432/ais`) — bukan produksi  
Rujukan: dok. 70 (penjaga), dok. 71/72 (lapis dasar), dok. 76 (pre-flight)

## Tindakan

`mode_proteksi_sql_endpoint` pada UAT dinaikkan dari `log` → **`enforce`**.
Sejak ini, pada endpoint `/Data`: `action=sql` yang bukan read-only satu
statement, menyentuh objek sistem, atau kolom kredensial DITOLAK; `action=update_data`
yang memuat DDL DITOLAK. DML biasa dan SELECT yang sah tetap jalan.

## Pre-flight diulang sebelum menaikkan

Seluruh SQL klien di basis kode disisir ulang pada kode terkini (bukan hanya saat
dok. 76):

| Pemeriksaan | Hasil |
| --- | --- |
| `action=sql` bukan diawali SELECT/WITH | 0 nyata (5 kandidat = 3 `console.error` log + 2 UPDATE yang dikirim via `action=update_data`, sah) |
| perintah tulis dikirim via `action=sql` | **0** |
| SQL klien menyentuh objek sistem | **0** |

Kesimpulan: **GO** — tidak ada halaman yang patah pada kode saat ini.

## Verifikasi

- Nilai DB sesudah perubahan = `enforce` (dikonfirmasi lewat koneksi baru).
- Tomcat UAT sedang **tidak berjalan**, sehingga tidak ada cache konfigurasi basi;
  boot berikutnya membaca `enforce` langsung dari basis data.
- Logika keputusan penjaga (tolak tulis/DDL/objek sistem/kolom kredensial, izinkan
  SELECT) sudah dikunci `SqlSecurityGuardSelfTest` (20/20, tanpa basis data).
- Batas jujur: perilaku **memblokir pada request langsung** belum diuji karena
  UAT Tomcat tidak berjalan dan jalur baca-konfigurasi penjaga menggantung di luar
  container. Pembuktian request-level dilakukan saat UAT dijalankan dan dipakai
  menguji.

## Cara membalik (bila ada yang tak terduga)

```sql
UPDATE public.konfigurasi SET nilai = 'log'
 WHERE nama = 'mode_proteksi_sql_endpoint';   -- atau 'off'
```

Berlaku setelah cache konfigurasi disegarkan (layar Konfigurasi) atau Tomcat
di-restart. Dua lapis dasar (tulis anonim ditutup, kolom kredensial diblokir)
tetap aktif apa pun nilainya (dok. 71/72).

## Produksi

Belum. Untuk ebisnis.id: pasang build server, jalankan SQL yang sama dengan
urutan `log` → amati → `enforce` (dok. 70/76), sesudah cadangan.
