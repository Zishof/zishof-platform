# Fase implementasi modul Pergudangan

Tanggal: 25 Agustus 2026  
Status: **rencana implementasi; belum ada perubahan kode modul**  
Dokumen induk: [Analisis implementasi modul Pergudangan](2026-08-25-analisis-modul-pergudangan.md)

## 1. Tujuan dokumen

Dokumen ini menerjemahkan analisis modul Pergudangan menjadi urutan pekerjaan yang
dapat dieksekusi, diuji, dan dirilis secara bertahap. Setiap fase memiliki batas yang
jelas supaya perubahan tidak merusak POS, pengadaan, retur, stok opname, Apotik,
produksi, laporan, dan integrasi akuntansi yang sudah berjalan.

Prinsip pelaksanaan:

- ledger stok yang sudah ada tetap menjadi fondasi; tidak membuat ledger paralel;
- perubahan database bersifat kompatibel ke belakang sampai cutover selesai;
- satu kontrak bisnis server dipakai Desktop, Android, JSP, dan ZK;
- semua write operation menggunakan idempotency key dan transaksi database;
- uang dan kuantitas presisi memakai `BigDecimal`/`numeric`, bukan `double`;
- kode server kompatibel Java 1.7 dengan gaya Java 1.6;
- `openSession()`/`currentNativeSession()` selalu dibersihkan dan ditutup di
  `finally`; `currentSession()` tidak ditutup manual;
- setiap fase berada di balik feature flag per tenant/toko;
- fase berikutnya dimulai hanya setelah exit criteria fase sebelumnya terpenuhi.

## 2. Urutan fase dan dependensi

| Fase | Nama | Ketergantungan | Hasil utama |
|---:|---|---|---|
| 0 | Keputusan arsitektur dan audit | - | kontrak stok, ownership data, baseline |
| 1 | Fondasi gudang, lokasi, dan hak akses | Fase 0 | master gudang/lokasi siap digunakan |
| 2 | Ledger pergerakan dan proyeksi saldo | Fase 1 | sumber mutasi konsisten dan dapat direkonsiliasi |
| 3 | Penerimaan, QC, putaway, dan transfer | Fase 2 | operasi masuk dan antargudang lengkap |
| 4 | Stock opname, adjustment, dan retur | Fase 3 | kontrol fisik dan koreksi teraudit |
| 5 | Lot, serial, kedaluwarsa, dan fulfillment | Fase 4 | traceability serta picking/pengiriman |
| 6 | Replenishment dan procurement suggestion | Fase 5 | min/max, reorder, usulan PO/transfer |
| 7 | Valuasi, akuntansi, laporan, dan analitik | Fase 2-6 | nilai stok dan laporan cutoff konsisten |
| 8 | Paritas kanal, migrasi, cutover, dan hardening | Semua | rilis produksi lintas kanal |

Fase 7 boleh dimulai sebagian setelah Fase 2 untuk laporan dasar, tetapi laporan
lanjut hanya dinyatakan selesai setelah proses bisnis Fase 3-6 tersedia.

## 3. Fase 0 - keputusan arsitektur dan audit

### Sasaran

Menghilangkan ketidakjelasan ownership data dan mendokumentasikan seluruh jalur yang
dapat mengubah stok sebelum schema atau logic baru dibuat.

### Pekerjaan

1. Putuskan apakah `sirs.Gudang` menjadi master gudang enterprise atau diganti model
   netral pada package inventory.
2. Putuskan posisi `asset.Lokasi`: dipakai langsung, diperluas, atau diberi adapter
   inventory agar tidak membawa semantik aset ke seluruh operasi gudang.
3. Inventarisasi semua write path stok:
   - pembayaran/penjualan POS;
   - transaksi tertahan yang dibayar;
   - pengadaan/kulakan;
   - retur pembelian dan penjualan;
   - mutasi antaroutlet;
   - stok opname;
   - pemakaian bahan baku dan produksi;
   - Apotik, batch, dan kedaluwarsa;
   - import, koreksi supervisor, migrasi, dan data sample.
4. Tetapkan definisi formal:
   - `on_hand`;
   - `available`;
   - `reserved`;
   - `incoming`;
   - `outgoing`;
   - `in_transit`;
   - `quarantine`;
   - `damaged`.
5. Pilih metode valuasi awal: moving average, FIFO, atau kebijakan per kategori.
6. Tetapkan kapan stok penerimaan diakui: saat receipt, setelah QC, atau setelah
   putaway.
7. Tetapkan matriks permission, approval, dan batas toleransi selisih.
8. Ambil baseline dari database uji/produksi:
   - saldo per toko/produk/batch;
   - jumlah movement per sumber;
   - transaksi tanpa referensi;
   - saldo negatif;
   - duplikasi referensi;
   - performa query utama;
   - jumlah koneksi dan `idle in transaction`.

### Artefak wajib

- ADR ownership Gudang dan Lokasi;
- katalog write path beserta kelas/method dan tabel terdampak;
- kamus status dan formula saldo;
- matriks peran dan izin;
- spesifikasi idempotency key;
- baseline rekonsiliasi yang dapat dijalankan ulang;
- kontrak API versi awal.

### Exit criteria

- delapan keputusan pada dokumen analisis telah disetujui;
- tidak ada write path stok yang belum mempunyai owner;
- formula saldo memberikan hasil yang sama dengan baseline yang disepakati;
- strategi rollback dan feature flag disetujui;
- tidak ada coding fitur sebelum keputusan tersebut tercatat.

## 4. Fase 1 - fondasi gudang, lokasi, dan hak akses

### Sasaran

Menyediakan master fisik dan virtual yang stabil tanpa mengubah total stok lama.

### Cakupan data

- gudang;
- zona;
- lorong/rak/bin;
- lokasi virtual: supplier, pelanggan, transit, retur, karantina, rusak, hilang,
  produksi, dan penyesuaian;
- hubungan toko-gudang;
- lokasi default untuk data lama;
- akses pengguna/peran ke gudang dan lokasi.

### Pekerjaan server dan database

1. Tambahkan schema/kolom secara nullable dan migrasi idempoten.
2. Buat constraint kode unik dalam scope tenant/gudang.
3. Cegah parent cycle pada hierarki gudang/lokasi.
4. Buat indeks pencarian nama, kode, parent, toko, jenis, dan status aktif.
5. Buat service tunggal untuk validasi tenant, toko, gudang, dan lokasi.
6. Backfill lokasi default bertanda `MIGRASI_AWAL`; tidak mengubah jumlah stok.
7. Tambahkan audit create/update/activate/deactivate.
8. Tambahkan feature flag `pergudangan_aktif` per tenant/toko dengan default tidak
   aktif.

### Pekerjaan UI

- menu **Pergudangan** dan sub-menu **Gudang & Lokasi**;
- tree gudang-lokasi dengan pencarian dan status aktif;
- form CRUD responsif;
- pemilih toko/gudang sesuai permission;
- Desktop/JSP/ZK memiliki fungsi administrasi lengkap;
- Android mengutamakan pencarian, scan, dan detail operasional.

### UAT minimum

- CRUD gudang/lokasi dan validasi duplikasi;
- lokasi virtual wajib tersedia dan tidak bisa dihapus saat telah digunakan;
- pengguna gudang A tidak dapat membaca/mengubah gudang B;
- admin tidak otomatis melewati scope tenant;
- data lama masuk ke lokasi default tanpa perubahan saldo.

### Exit criteria

- master dan permission lulus UAT pada minimal dua toko dan dua gudang;
- backfill dapat diulang tanpa membuat data ganda;
- API lama tetap memberikan hasil sama;
- feature flag dapat menyalakan/mematikan UI tanpa kehilangan data.

## 5. Fase 2 - ledger pergerakan dan proyeksi saldo

### Sasaran

Menyatukan semua perubahan stok ke kontrak posting yang konsisten, teraudit, dan
idempoten.

### Model konseptual

Setiap movement minimum memuat:

- tenant, toko, gudang, lokasi asal, dan lokasi tujuan;
- produk, UOM, kuantitas, batch/serial bila ada;
- tipe movement dan status;
- waktu bisnis dan waktu pencatatan;
- jenis/id dokumen sumber;
- idempotency key;
- pengguna, perangkat, dan alasan;
- nilai unit/total dan referensi jurnal bila relevan;
- movement reversal bila dibatalkan.

### Pekerjaan

1. Buat `InventoryPostingService` sebagai satu pintu posting movement.
2. Adaptasikan sumber lama secara bertahap; jangan melakukan dual-write permanen.
3. Tambahkan unique constraint untuk idempotency key dan referensi sumber.
4. Buat proyeksi saldo per produk-lokasi-batch serta reserved/transit.
5. Buat kartu stok yang diturunkan dari ledger.
6. Buat job rekonsiliasi dan rebuild projection yang resumable.
7. Buat checksum dan laporan ketidaksesuaian saldo lama vs proyeksi baru.
8. Terapkan reversal; histori movement terposting tidak boleh dihapus/diubah bebas.
9. Tambahkan optimistic/pessimistic locking sesuai jalur transaksi untuk mencegah
   oversell dan lost update.
10. Pastikan paging, filter server-side, dan query indeks untuk volume besar.

### Strategi aktivasi

1. **Shadow read**: proyeksi baru dihitung tetapi belum dipakai operasi.
2. **Reconciliation**: hasil lama dan baru dibandingkan otomatis.
3. **Read cutover**: layar tertentu membaca proyeksi baru.
4. **Write cutover**: write path dipindahkan satu per satu ke posting service.
5. Adapter lama dipertahankan selama masa kompatibilitas.

### UAT minimum

- retry request yang sama tidak membuat movement ganda;
- dua kasir menjual produk/lokasi sama tanpa lost update;
- reversal mengembalikan saldo dan nilai secara tepat;
- saldo projection sama dengan agregasi ledger;
- inventory at timestamp dapat direproduksi;
- satu juta movement tetap memenuhi target performa.

### Exit criteria

- rekonsiliasi saldo 100% untuk data bersih atau seluruh perbedaan memiliki tiket
  dan alasan yang disetujui;
- tidak ada kebocoran native session atau `idle in transaction` dari jalur baru;
- write path POS dan pengadaan lulus concurrency/idempotency test;
- rollback ke read path lama telah diuji.

## 6. Fase 3 - penerimaan, QC, putaway, dan transfer

### Sasaran

Menyelesaikan aliran barang masuk dan perpindahan antargudang secara nyata.

### Modul penerimaan

- receipt dari PO/pengadaan atau penerimaan tanpa PO dengan izin khusus;
- scan produk/batch/serial;
- qty dipesan, diterima, ditolak, rusak, dan tersisa;
- QC dan lokasi karantina;
- putaway ke lokasi final;
- penerimaan parsial dan backorder;
- dokumen, foto, catatan, supplier, dan pengguna penerima.

### Modul transfer

- draft permintaan transfer;
- persetujuan jika diwajibkan;
- picking lokasi asal;
- pengiriman ke lokasi transit;
- penerimaan penuh/parsial/lebih/kurang/rusak;
- backorder atau penutupan sisa;
- bukti serah terima dan audit asal-tujuan.

### State machine

`DRAFT -> DIAJUKAN -> DISETUJUI -> DIPICK -> DIKIRIM -> TRANSIT -> DITERIMA`

Cabang status yang diizinkan: `DITOLAK`, `DIBATALKAN`, `DITERIMA_SEBAGIAN`, dan
`BERMASALAH`. Transisi mundur dilakukan dengan reversal/aksi koreksi, bukan mengganti
status sembarang.

### UI operasional

- dashboard antrean receipt, putaway, transfer keluar, transit, dan transfer masuk;
- scan-first, keyboard-friendly di Desktop, satu tangan di Android;
- indikator progres dan konflik real-time;
- cetak/ekspor dokumen transfer dan penerimaan;
- detail tetap dalam halaman/modal bila konteks kerja perlu dipertahankan.

### UAT minimum

- penerimaan penuh, parsial, rusak, lebih, dan kurang;
- transfer A -> transit -> B tidak mengubah total enterprise;
- double submit/scan tidak menggandakan item;
- penerimaan oleh perangkat lain memperbarui status tanpa reload penuh;
- transaksi lama tetap tampil melalui adapter.

### Exit criteria

- seluruh skenario state transition dan reversal lulus;
- selisih transfer selalu mempunyai owner dan resolusi;
- bukti audit dapat ditelusuri dari dokumen ke movement dan kembali;
- operasi stabil pada koneksi lambat dan retry.

## 7. Fase 4 - stock opname, adjustment, dan retur

### Sasaran

Memberikan mekanisme kontrol fisik yang deterministik dan koreksi yang dapat diaudit.

### Stock opname

- full count, cycle count, blind count, dan spot check;
- snapshot saldo pada waktu mulai;
- assignment lokasi/petugas;
- input/scan hitungan fisik;
- hitung movement setelah snapshot;
- recount berdasarkan toleransi;
- approval supervisor;
- posting adjustment dan jurnal;
- pembekuan terbatas hanya bila dibutuhkan.

### Adjustment

- alasan baku dan catatan wajib;
- batas nominal/qty sesuai approval matrix;
- perpindahan ke/dari lokasi virtual penyesuaian;
- reversal koreksi, bukan hard delete.

### Retur

- retur pembelian kembali ke supplier;
- retur penjualan ke stok baik, QC, karantina, atau rusak;
- referensi transaksi asal;
- dampak nilai, pajak, diskon, dan jurnal;
- lot/serial yang sama dengan transaksi asal jika diwajibkan.

### UAT minimum

- transaksi berjalan setelah snapshot tidak menghasilkan selisih semu;
- recount dan approval mengikuti tolerance;
- retur tidak menambah/mengurangi stok dua kali;
- adjustment dan reversal seimbang pada stok serta jurnal;
- offline draft tidak mem-posting adjustment sebelum server mengonfirmasi.

### Exit criteria

- hasil opname dapat direproduksi dari snapshot dan movement;
- seluruh selisih mempunyai alasan, petugas, dan approval;
- laporan stok total tetap sama dengan ledger setelah adjustment/retur.

## 8. Fase 5 - lot, serial, kedaluwarsa, dan fulfillment

### Sasaran

Melengkapi traceability produk dan proses pengeluaran gudang.

### Lot/serial/expiry

- lot/batch saat penerimaan;
- serial unik sesuai scope tenant/produk;
- expiry, best-before, removal date, dan end-of-life;
- FEFO/FIFO otomatis;
- override supervisor dengan alasan;
- recall per lot/serial;
- karantina dan blokir transaksi produk kedaluwarsa.

### Fulfillment

- reservasi stok;
- allocation per lokasi/batch;
- picking list/wave picking sederhana;
- scan konfirmasi;
- packing dan shipment;
- short pick, substitution bila diizinkan, serta backorder;
- pelepasan reservasi saat batal/timeout.

### UAT minimum

- serial tidak dapat diterima/dikirim dua kali;
- FEFO memilih batch dengan expiry paling dekat yang masih valid;
- recall menemukan seluruh receipt, movement, dan sale terkait;
- reservasi bersaing tidak melebihi available stock;
- pembatalan order melepaskan reservasi tepat satu kali.

### Exit criteria

- traceability dua arah lengkap dari supplier sampai transaksi keluar;
- produk batch/serial dan produk biasa sama-sama tetap berjalan;
- POS/Apotik memakai aturan batch/expiry server yang sama.

## 9. Fase 6 - replenishment dan procurement suggestion

### Sasaran

Menghasilkan rekomendasi pengisian yang dapat dijelaskan, bukan pemesanan otomatis
yang tidak terkendali.

### Pekerjaan

- min/max dan safety stock per produk-lokasi;
- lead time supplier dan transfer;
- reorder point;
- preferred supplier dan alternatif;
- usulan draft PO atau transfer internal;
- peringatan stok rendah/stockout;
- parameter musiman dan konsumsi rata-rata;
- scheduler aman, idempoten, dan dapat dihentikan/dilanjutkan;
- halaman review/approve sebelum PO/transfer dibuat.

Formula awal yang direkomendasikan:

`reorder_point = kebutuhan_selama_lead_time + safety_stock`

Formula harus dapat dikonfigurasi dan menampilkan komponen perhitungan kepada
pengguna.

### UAT minimum

- rekomendasi tidak menggandakan draft pada rerun;
- on-order, in-transit, reserved, dan available dihitung tepat;
- supplier/lead time kosong menghasilkan peringatan, bukan transaksi salah;
- approval menghasilkan referensi yang dapat dilacak ke rekomendasi.

### Exit criteria

- rekomendasi dapat dijelaskan dan dibandingkan dengan data sumber;
- scheduler tidak menahan request HTTP dan tidak meninggalkan transaksi terbuka;
- tidak ada PO otomatis tanpa persetujuan pada fase awal.

## 10. Fase 7 - valuasi, akuntansi, laporan, dan analitik

### Sasaran

Menjamin kuantitas dan nilai persediaan konsisten pada tanggal cutoff.

### Valuasi dan jurnal

- metode biaya yang disetujui pada Fase 0;
- layer biaya dan landed cost bila termasuk scope;
- jurnal penerimaan, pengeluaran, transfer antarentitas, adjustment, retur, dan
  reversal;
- link satu-ke-satu atau satu-ke-banyak antara dokumen, movement, cost layer, dan
  jurnal;
- rekonsiliasi subledger inventory dengan buku besar.

### Laporan minimum

- saldo stok per tanggal;
- kartu stok per produk/lokasi/batch;
- inventory valuation per tanggal;
- stok transit dan transfer outstanding;
- barang karantina/rusak/hilang;
- expiry dan aging;
- slow/fast moving;
- akurasi opname;
- fill rate, stockout, dan lead time;
- reorder recommendation history.

### Ketentuan teknis

- seluruh filter bertipe jelas; parameter kosong tidak dilempar sebagai bigint/date;
- query PostgreSQL tidak memakai `::type` pada Hibernate SQLQuery lama bila parser
  dapat menganggapnya named parameter; gunakan `CAST(... AS type)`;
- laporan besar dijalankan sebagai background job dan mempunyai progres;
- preview memakai pagination; ekspor PDF/Excel tidak bergantung pada data grid yang
  sedang terlihat;
- inventory at date berasal dari ledger/projection cutoff, bukan saldo hari ini.

### UAT minimum

- total valuasi per lokasi = total valuasi enterprise;
- inventory subledger = akun persediaan GL pada cutoff;
- reversal tidak meninggalkan nilai yatim;
- laporan tanggal lampau stabil walaupun ada transaksi baru;
- ekspor dan preview menghasilkan angka sama.

### Exit criteria

- rekonsiliasi quantity dan value lulus pada beberapa cutoff;
- seluruh ketidakseimbangan memiliki detail drill-down;
- laporan p95 dan background export memenuhi target performa.

## 11. Fase 8 - paritas kanal, migrasi, cutover, dan hardening

### Sasaran

Menjadikan modul siap produksi tanpa memutus fungsi lama.

### Paritas kanal

| Kanal | Cakupan minimum |
|---|---|
| Desktop | seluruh operasi gudang, scan, approval, laporan, konfigurasi |
| Android | scan, receipt, putaway, picking, transfer, count, status |
| JSP | administrasi, operasi inti, laporan, kompatibilitas deployment server |
| ZK | administrasi/back-office sesuai akses dan kontrak bisnis yang sama |

Paritas berarti hasil bisnis sama; layout boleh adaptif terhadap perangkat.

### Migrasi dan cutover

1. Dry run migrasi pada salinan database produksi.
2. Backfill lokasi default dan movement historis secara resumable.
3. Rekonsiliasi per toko/produk/batch/nilai.
4. Aktifkan shadow read.
5. Aktifkan read path baru untuk pengguna pilot.
6. Aktifkan write path per toko secara bertahap.
7. Monitor error, latency, lock, koneksi, saldo negatif, dan mismatch.
8. Perluas rollout setelah masa stabil.
9. Pertahankan adapter lama sampai exit criteria terpenuhi.

### Hardening

- security test tenant/scope/IDOR;
- concurrency dan retry storm;
- offline/online transition;
- restore backup dan disaster recovery;
- load test 50.000 produk, 5.000 lokasi, 1.000.000 movement, 100 pengguna;
- observability: request ID, document ID, movement ID, device, user, duration;
- runbook operasional dan support.

### Exit criteria akhir

- seluruh UAT fungsional, kompatibilitas, keamanan, dan beban lulus;
- saldo lama dan baru telah direkonsiliasi;
- rollback rehearsal lulus;
- dokumentasi operator, supervisor, admin, dan developer tersedia;
- semua perubahan dicatat di `/docs/pos`;
- build/release hanya dilakukan setelah persetujuan UAT.

## 12. Feature flag dan rollback

Feature flag minimum:

- `pergudangan_aktif`;
- `pergudangan_ledger_baru_aktif`;
- `pergudangan_receiving_aktif`;
- `pergudangan_transfer_aktif`;
- `pergudangan_opname_baru_aktif`;
- `pergudangan_traceability_aktif`;
- `pergudangan_replenishment_aktif`;
- `pergudangan_laporan_baru_aktif`.

Aturan rollback:

- mematikan flag menghentikan entry baru lewat UI, bukan menghapus data;
- movement yang telah terposting tetap immutable;
- transaksi setengah jalan harus dapat dilanjutkan atau dibatalkan dengan reversal;
- rollback schema tidak dilakukan dengan menghapus kolom/tabel berisi data;
- adapter read lama dipertahankan sampai cutover final;
- setiap migrasi mempunyai checkpoint, checksum, dan kemampuan resume.

## 13. Definition of Done setiap fase

Sebuah fase baru dinyatakan selesai bila:

1. implementasi server, database, dan kanal yang termasuk scope selesai;
2. permission divalidasi server-side;
3. migrasi idempoten dan rollback operasional diuji;
4. unit/integration/UAT/concurrency test terkait lulus;
5. Java 1.7 dan aturan lifecycle Hibernate dipenuhi;
6. query utama mempunyai indeks dan bukti explain/performa;
7. API terdokumentasi dan kompatibilitas lama diuji;
8. tidak ada error baru, session leak, atau `idle in transaction`;
9. hasil dan perubahan dicatat di `/docs/pos`;
10. reviewer bisnis dan teknis menyetujui exit criteria.

## 14. Urutan backlog awal setelah persetujuan

Urutan pekerjaan pertama yang direkomendasikan:

1. ADR master Gudang/Lokasi.
2. Audit write path stok dan baseline query.
3. Kamus formula saldo dan status.
4. Matriks permission dan approval.
5. Schema master lokasi + feature flag.
6. API CRUD gudang/lokasi.
7. UI master Gudang & Lokasi.
8. Posting service dan idempotency.
9. Projection + reconciliation job.
10. Kartu stok per lokasi.
11. Pilot shadow-read pada satu toko demo.
12. Baru dilanjutkan ke receiving dan transfer.

## 15. Keputusan sebelum memulai Fase 0

Pemilik produk perlu mengonfirmasi:

1. varian pertama untuk pilot;
2. toko/gudang pilot;
3. owner master Gudang dan Lokasi;
4. metode valuasi awal;
5. waktu pengakuan stok penerimaan;
6. kebutuhan serial pada rilis pertama;
7. kebijakan offline untuk mutation;
8. batas approval selisih dan transfer;
9. apakah transfer antartoko berada dalam satu entitas akuntansi;
10. kanal yang wajib tersedia pada pilot pertama.

Setelah keputusan tersebut disetujui, pekerjaan dimulai dari Fase 0 dan tidak
langsung melompat ke pembuatan seluruh menu. Pendekatan ini menjaga fungsi lama,
memungkinkan rekonsiliasi, dan membatasi risiko perubahan stok serta akuntansi.
