# Implementasi Fase 1 — Kontrak Menu, Alias, dan Aksi Granular

Tanggal: 25 Agustus 2026  
Status: **kode fondasi dan UAT terarah selesai; belum dipublikasikan**

## Tujuan fase

Fase ini membangun kontrak hak akses yang stabil sebelum menu Pengadaan,
Pergudangan, Distribusi, Produksi, Keuangan, dan POS dihubungkan ke workflow
baru. Fokusnya bukan memindahkan sidebar atau membuat tabel transaksi baru,
melainkan memastikan nama menu dan nama aksi lama tetap kompatibel ketika
kontrak baru diperkenalkan.

## Perubahan kode

### Registry kanonik dan alias

`ais.common.EbisnisMenuActionRegistry` menjadi satu sumber normalisasi:

- alias menu lama seperti `pr`, `permintaan_pembelian`, dan
  `purchase_requisition` mengarah ke `pengadaan_pr`;
- pola yang sama tersedia untuk PO, BAST, tagihan vendor, pembayaran vendor,
  kulakan, mutasi outlet, stok opname, retur, laporan, dan produksi;
- alias aksi lama dan istilah UI dinormalisasi ke aksi kanonik;
- registry fail-fast bila satu alias dipetakan ke dua kanonik berbeda.

### Kontrak aksi granular

Aksi kanonik yang dikenali:

1. `view`
2. `create`
3. `update` — juga mewakili istilah blueprint `EDIT_DRAFT`
4. `delete`
5. `submit`
6. `approve`
7. `reject`
8. `cancel`
9. `post`
10. `reverse`
11. `export`
12. `view_cost`
13. `view_all_location`

Kebijakan kompatibilitas:

- lima aksi historis `create`, `update`, `delete`, `approve`, dan `reject`
  tetap default-allow untuk role lama yang belum memiliki konfigurasi aksi;
- aksi workflow baru bersifat **fail-closed** sampai diizinkan eksplisit;
- aksi historis yang belum terdaftar tidak langsung diputus agar endpoint lama
  tetap berjalan selama masa inventarisasi;
- flag `supervisor` tetap bypass semua aksi;
- pemeriksaan visibilitas menu tetap terpisah dari pemeriksaan aksi.

## Lokasi source

Perubahan dicerminkan identik pada dua source tree server:

- `C:/opt/AIS/ais/src/main/src/ais/common/EbisnisMenuActionRegistry.java`
- `C:/opt/AIS/ais/src/main/java/ais/common/EbisnisMenuActionRegistry.java`
- `C:/opt/AIS/ais/src/main/src/ais/common/EbisnisMenuKatalog.java`
- `C:/opt/AIS/ais/src/main/java/ais/common/EbisnisMenuKatalog.java`

Hash kedua pasangan telah diverifikasi identik.

## UAT yang telah dijalankan

### Registry

Kompilasi menggunakan `javac -source 1.7 -target 1.7` dan menjalankan
`EbisnisMenuActionRegistryUat`.

Hasil:

```text
UAT EbisnisMenuActionRegistry: LULUS
```

Kasus yang diuji meliputi alias menu, alias aksi, validasi bentrok, aksi
terdaftar, dan aksi yang tidak dikenal.

### Keputusan izin katalog

Kompilasi terarah Java 1.7 dan menjalankan
`EbisnisMenuKatalogAksiUat`.

Hasil:

```text
UAT EbisnisMenuKatalog aksi granular: LULUS
```

Kasus yang diuji:

- `create` pada role lama tetap boleh;
- `submit` pada role lama ditolak;
- izin `ajukan` pada alias menu lama terbaca sebagai `submit` pada menu
  kanonik;
- supervisor boleh melakukan `reverse`;
- aksi historis yang belum terdaftar tidak diputus pada fase kompatibilitas.

## Catatan kompilasi penuh

Target Ant `compile` telah dicoba. Build berhenti sebelum pemeriksaan seluruh
source karena `C:/opt/AIS/ais/ant/build.xml` masih mengharapkan direktori
deployment `C:/opt/AIS/ais/web/WEB-INF/lib`, sedangkan library checkout berada
di `src/main/webapp/WEB-INF/lib`.

Pesan aktual:

```text
BUILD FAILED
C:\opt\AIS\ais\ant\build.xml:109:
C:\opt\AIS\ais\web\WEB-INF\lib does not exist.
```

Ini adalah gerbang lingkungan build, bukan kegagalan kompilasi pada dua kelas
yang diubah. Kelas yang diubah telah lulus kompilasi terarah Java 1.7.

## Yang belum dianggap selesai

Fase ini belum berarti seluruh endpoint telah memakai aksi granular. Pekerjaan
lanjutan wajib dilakukan bertahap:

1. petakan setiap endpoint mutasi ke menu dan aksi kanonik;
2. pasang gerbang server-side, bukan hanya hide/show tombol;
3. pastikan `Common.apakahAdmin() == true` memberi akses semua menu melalui
   jalur admin yang sudah diaudit;
4. migrasikan konfigurasi role secara idempoten tanpa mengubah keputusan role
   lama;
5. lakukan UAT Desktop, Android, JSP, dan ZKoss;
6. selesaikan snapshot schema, golden dataset, dan uji backup/restore sebelum
   DDL Fase 2 dieksekusi.

## Batas fase berikutnya

Dokumen dan SQL preflight Fase 2 sudah tersedia, tetapi DDL produksi belum
dijalankan. Fase 2 baru boleh masuk implementasi fisik setelah gerbang baseline
Fase 0 dinyatakan lulus dan target database terisolasi tersedia.

