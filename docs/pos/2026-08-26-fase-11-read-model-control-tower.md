# Fase 11 — Read Model Laporan dan Control Tower

Tanggal: 26 Agustus 2026

## Outcome

Fase ini menyediakan fondasi laporan lintas domain yang ringan, dapat direkonsiliasi, dan konsisten antara kartu KPI, tabel, drill-down, serta ekspor. Implementasi belum mengaktifkan query agregasi terhadap produksi dan belum menjalankan DDL apa pun.

## Ruang lingkup

Control tower akan menyatukan indikator dari replenishment, procurement, inbound, inventory, outbound/distribusi, produksi, Accounts Payable/akuntansi, penjualan/POS, dan audit. Setiap indikator wajib mempunyai:

- kode dan label yang stabil;
- pemilik bisnis;
- sumber kebenaran;
- rute drill-down ke dokumen sumber;
- kueri rekonsiliasi yang dapat diaudit;
- snapshot dan watermark yang sama untuk layar maupun ekspor.

## Arsitektur

Aliran data yang dipilih:

`OLTP/domain source -> adapter agregasi eksplisit/terjadwal -> snapshot immutable + watermark -> UI/paging/export`

Keputusan penting:

1. `loadInitial()` hanya membaca snapshot terakhir. Halaman pertama tidak boleh menjalankan agregasi besar pada tabel OLTP.
2. Bila snapshot belum tersedia, layanan mengembalikan snapshot kosong berstatus `STALE`, bukan diam-diam menjalankan query berat.
3. `refresh()` adalah operasi eksplisit melalui adapter read-model. Hasilnya disimpan sebagai snapshot `READY` dengan filter key dan watermark.
4. `loadForExport()` mengambil snapshot `READY` yang sama berdasarkan ID snapshot. Dengan demikian angka di kartu, grid, drill-down, dan berkas ekspor tidak berbeda akibat waktu query yang berlainan.
5. Filter membawa tenant, lokasi opsional, rentang tanggal, limit, dan offset. Limit server-side dibatasi 1–500.
6. Definisi KPI yang tidak lengkap atau kode KPI duplikat ditolak sebelum snapshot disimpan.
7. Koleksi dalam snapshot bersifat immutable dan semua nilai tanggal menggunakan defensive copy.

## Implementasi kode

Sumber otoritatif berada di `C:\opt\AIS\ais\src\main\src`, dengan mirror identik di `C:\opt\AIS\ais\src\main\java`:

- `ais.common.inventory.controltower.ControlTowerTypes`
- `ais.common.inventory.controltower.ControlTowerReadModelPort`
- `ais.common.inventory.controltower.ControlTowerService`

UAT berada di:

- `C:\opt\AIS\ais\src\test\java\ais\common\inventory\controltower\ControlTowerServiceUat.java`

## Kontrak adapter berikutnya

Adapter database/scheduler/UI belum dipasang pada fase fondasi ini. Implementasi berikutnya wajib mematuhi aturan berikut:

- agregasi dilakukan per tenant dan rentang waktu, bukan scan global tanpa filter;
- pagination, sorting, dan filter dilakukan server-side;
- refresh menyimpan metric dan alert dalam satu Unit of Work dengan header snapshot;
- snapshot baru baru boleh berstatus `READY` setelah seluruh metric dan alert berhasil disimpan;
- kegagalan refresh tidak menghapus snapshot `READY` sebelumnya;
- adapter yang membuka `openSession()` atau `currentNativeSession()` wajib `clear`, `disconnect`, dan `close` di `finally`;
- `currentSession()` tidak ditutup manual;
- ekspor tidak menghitung ulang data dan wajib memakai snapshot ID yang terlihat pengguna.

## Draft skema

Draft review-only tersedia pada `2026-08-26-fase-11-schema-read-model-control-tower.sql`. Draft memisahkan header snapshot, nilai metric, dan alert/drill-down. Tidak ada DDL/DML yang dijalankan dari pekerjaan ini.

## UAT

`ControlTowerServiceUat` dikompilasi menggunakan `javac -source 1.7 -target 1.7` dan lulus 22 assertion, mencakup:

- initial load tidak memicu agregasi;
- fallback `STALE` saat snapshot belum ada;
- refresh eksplisit dan penyimpanan watermark;
- batas alert mengikuti limit server-side;
- metadata KPI lengkap;
- snapshot ekspor identik dengan snapshot layar;
- koleksi immutable dan tanggal defensive-copy;
- penolakan limit tidak valid, snapshot ekspor hilang, dan kode KPI duplikat.

Output kompilasi ditempatkan di `.codex-build/fase11-control-tower`; tidak ada `.class` yang dibuat di samping `.java`.

## Gerbang sebelum aktivasi runtime

- DBA mereview dan menjalankan migration hanya pada database staging/UAT.
- Adapter untuk setiap domain memiliki query rekonsiliasi dan indeks yang terukur.
- UAT database membuktikan refresh atomik, retry idempoten, dan snapshot lama tetap tersedia saat refresh gagal.
- Uji performa membuktikan halaman pertama hanya membaca snapshot terindeks.
- UAT timezone membuktikan batas hari dan watermark konsisten di server, Desktop, Android, JSP, dan ZK.
- UAT paritas membuktikan kartu = grid = ekspor = drill-down untuk snapshot/filter yang sama.

## Rollback

Karena fondasi ini belum dihubungkan ke runtime, rollback kode cukup melepas adapter/rute yang kelak ditambahkan. Saat migration sudah disetujui, rollback wajib menghapus objek read-model secara terbalik setelah consumer dinonaktifkan, tanpa menyentuh tabel sumber OLTP.

