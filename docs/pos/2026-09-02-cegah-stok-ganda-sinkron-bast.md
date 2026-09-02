# 79. Cegah Stok Ganda pada Sinkron BAST → Kulakan

Tanggal: 2 September 2026  
Modul: Pengadaan & Logistik (penerimaan barang → stok)  
Sifat: perbaikan bug integritas stok (race condition)

## Bug

`PengadaanPosApiHelper.bastSinkronKulakan` mengubah Penerimaan Barang (BAST) yang
sudah disetujui menjadi stok lewat jalur Kulakan resmi. Penjaga anti-ganda-nya:

```java
if (bast.getPengadaanFaktur() != null) { tolak("...akan menggandakan stok"); return; }
```

Masalahnya, **pengecekan** penjaga dan **penandaan** faktur berada di **dua
transaksi berbeda**, dengan pemanggilan `KantinHelper.kulakanFakturSimpan` (yang
menambah stok) di antaranya, **tanpa kunci**:

1. baca `getPengadaanFaktur()` → null (transaksi A, lalu ditutup);
2. `kulakanFakturSimpan` → buat faktur + tambah stok (transaksi B sendiri);
3. tandai `bast.setPengadaanFaktur(faktur)` (transaksi C).

Dua permintaan bersamaan untuk BAST yang sama — sinkron otomatis saat `SETUJUI`
beririsan dengan tombol **Sinkron** manual, atau **retry offline** — dapat
sama-sama lolos langkah 1, sama-sama menjalankan langkah 2, dan **menambah stok
dua kali**. Komentar penjaga yang menyatakan "penolakan ganda tidak menggandakan
stok" hanya benar untuk pengulangan **berurutan** (sesudah faktur tertulis).

## Perbaikan

Serialisasi per-BAST memakai **advisory lock Postgres** — idiom yang sama dengan
`OnlineBmt`:

```java
SELECT pg_try_advisory_lock(hashtext('bast-sinkron:' + id))
```

- Pemanggil yang **menang** memproses sampai selesai lalu melepas kunci
  (`pg_advisory_unlock`, di `finally`; kunci juga lepas otomatis saat koneksi
  ditutup, jadi tidak bocor meski unlock gagal).
- Pemanggil yang **kalah** ditolak "sedang disinkronkan oleh proses lain" dan
  boleh mencoba ulang — saat itu penjaga `getPengadaanFaktur()` sudah menangkapnya
  sebagai "sudah disinkronkan".

Tanpa kolom/skema baru; logika sinkron yang ada tidak diubah, hanya dibungkus
gerbang kunci. Kunci dipegang oleh satu session (`kunci`) yang terbuka sepanjang
method, terpisah dari session Kulakan.

## Bukti

- **SQL advisory lock** diuji langsung via JDBC dua koneksi: koneksi-1 menahan
  kunci → koneksi-2 `pg_try_advisory_lock` mengembalikan **false** → koneksi-1
  melepas → koneksi-2 mengembalikan **true**. Perilaku mutual-exclusion yang
  persis diandalkan perbaikan ini terbukti.
- **Kompilasi** bersih (javac 1.7).
- **Harness end-to-end** `TesBastSinkronLock` (gerbang menolak saat kunci
  ditahan; lolos saat lepas; kunci tidak bocor sesudah selesai) **sudah siap**
  tetapi belum dijalankan: SessionFactory UAT sementara gagal dibangun karena
  entitas milik sesi lain yang setengah ter-deploy (`GrupItemBiayaSekolah`) —
  tidak terkait perubahan ini. Akan dijalankan begitu lingkungan stabil.

## Catatan penerapan

Berlaku setelah build server dipasang dan Tomcat di-restart. Advisory lock
bersifat per-database dan otomatis lepas saat koneksi berakhir, jadi aman untuk
banyak node aplikasi yang berbagi satu basis data.
