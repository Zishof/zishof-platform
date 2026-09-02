# 68. Batas Baris Laporan, Self-Test Aturan SQL, dan Nilai Dashboard

Tanggal: 2 September 2026  
Lanjutan: dok. 65 dan dok. 67 (perbaikan laporan penjualan)

## 1. Laporan web tidak lagi bisa menghabiskan memori server

Jalur eksekusi laporan membaca **seluruh** ResultSet ke memori sebagai `Object[]`
tanpa batas. Satu permintaan "Rincian Penjualan per Barang" untuk rentang setahun
pada toko ramai dapat menarik ratusan ribu baris sekaligus — membebani memori
server (bukan hanya laporan itu; seluruh aplikasi ikut terdampak) dan
menghasilkan halaman yang tidak mungkin dibaca.

Kini dibatasi **20.000 baris** lewat `ps.setMaxRows`. Bila batas tersentuh,
`Hasil.terpotong` disetel dan catatan laporan diawali:

> PERHATIAN: hanya 20000 baris pertama yang ditampilkan. Angka di bawah TIDAK
> lengkap — persempit rentang tanggal atau pakai filter produk/kasir.

Laporan yang diam-diam terpotong lebih berbahaya daripada laporan yang gagal:
angkanya terlihat wajar dan tetap dipakai untuk mengambil keputusan.

Bukti: harness membuat **20.001** baris nyata; laporan mengembalikan tepat
20.000 baris, `terpotong` bernilai true, dan catatannya memuat peringatan itu.

## 2. Self-test yang menjaga aturan SQL laporan

`LaporanKantinSqlSelfTest` (tanpa JUnit, **tanpa basis data**) mengunci lima
keputusan yang masing-masing pernah menjadi cacat nyata:

1. nilai penjualan diambil dari kolom final `p.total`, bukan dihitung ulang;
2. identitas kasir dari `kasir_login_nama`, **bukan** `h.oleh`;
3. label produk jatuh ke snapshot baris penjualan;
4. periode item penjualan selalu menyingkirkan baris tidak aktif;
5. ada batas jumlah baris yang masuk akal.

Jalankan:

```bash
java ais.action.master.koperasi.helper.LaporanKantinSqlSelfTest
```

Hasil saat ditulis: **11/11 lulus**. Konstanta SQL terkait dibuka dari `private`
menjadi package-private agar dapat dijaga self-test sepaket; tidak ada yang
menjadi publik.

## 3. Dashboard Stok menyebut angka yang sama dengan laporan

Kartu dan tabel **"Barang Keluar"** menghitung nilai sebagai `qty × hargajual` —
kolom harga jual pada BARIS penjualan. Pada baris yang dibuat POS kolom itu lazim
**kosong**, sehingga nilainya jatuh ke nol; bila terisi pun rumus itu mengabaikan
diskon, harga grosir, dan harga Pack.

Uji atas fixture nyata: rumus lama menghasilkan **0**, sedangkan nilai penjualan
sebenarnya **77.000**. Dashboard menyebut angka yang sama sekali berbeda dari
laporan penjualan untuk periode yang sama.

Kini memakai `COALESCE(a.total, a.qty*COALESCE(a.hargasatuan, a.hargajual, 0), 0)`
— sama seperti `LaporanKantinUtil.OMZET` dan seperti laporan retur yang memang
sudah memakai pola ini.

## 4. Indeks pendukung kueri laporan — disiapkan, belum masuk

Tabel `koperasi.pembelian` hanya punya indeks pada `produk` dan kunci utama,
padahal **setiap** laporan penjualan menyaring `toko` + rentang `waktu`. Tanpa
indeks itu, setiap pembukaan laporan memindai seluruh tabel item.

Dua indeks disiapkan di `InitIndex` (idempoten, `CREATE INDEX IF NOT EXISTS`):

```sql
CREATE INDEX IF NOT EXISTS idx_kop_pembelian_toko_waktu ON koperasi.pembelian (toko, waktu, aktif);
CREATE INDEX IF NOT EXISTS idx_kop_pembelian_nota ON koperasi.pembelian (pembelian_anggota_koperasi);
```

**Belum dikirim ke repositori**: berkas `InitIndex.java` sedang memuat pekerjaan
sesi lain yang belum selesai (±370 baris), dan mengirim berkas itu seluruhnya
berarti ikut mengklaim serta memublikasikan perubahan yang bukan milik pekerjaan
ini. Perubahan indeksnya menunggu di salinan kerja sampai berkas itu bersih.
Bila diperlukan lebih cepat, kedua perintah di atas aman dijalankan langsung oleh
admin basis data.

## Bukti

| Uji | Hasil |
| --- | --- |
| `LaporanKantinSqlSelfTest` (tanpa DB) | 11/11 |
| `TesLaporanWeb` (termasuk 20.001 baris dan konsistensi dashboard) | 22/22 |
