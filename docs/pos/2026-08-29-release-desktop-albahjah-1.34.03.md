# Rilis Desktop Al-Bahjah POS 1.34.03

Tanggal: 29 Agustus 2026  
Versi aplikasi: `1.34.03+161`  
Varian: `albahjah`  
Tag GitHub: `v1.34.03-build161`

## Ringkasan

- Satuan dasar/penjualan dan satuan pembelian produk memakai master UOM yang berelasi.
- Kuantitas dan harga pembelian dikonversi ke satuan dasar saat penerimaan, sedangkan satuan input dan faktor konversinya disimpan sebagai snapshot audit.
- Kemasan/barcode multi-unit dipisahkan dari UOM akuntansi. Pemindaian barcode kemasan di Kasir menambahkan kuantitas satuan dasar sesuai isi kemasan.
- Validasi mencegah UOM lintas kategori, faktor konversi tidak valid, serta barcode kemasan ganda.
- Pesan penolakan menjelaskan penyebab dan tindakan koreksi yang dapat dilakukan pengguna.

## Urutan penerapan

1. Jalankan `migrasi_uom_kategori_pembelian_20260828.sql` pada database server.
2. Deploy server/SVN revisi `r78484`.
3. Pasang desktop Al-Bahjah POS 1.34.03.
4. Tekan **Sinkronkan/Muat Ulang** agar master UOM dan produk terbaru masuk ke cache lokal.

Jangan memasang desktop sebelum migrasi dan server baru aktif karena penyimpanan produk/pembelian memakai kolom dan kontrak API baru.

## UAT

- Analisis statis Flutter pada modul UOM, produk, pembelian, dan kasir: lulus.
- Seluruh pengujian aplikasi Flutter: 437 lulus.
- Seluruh pengujian `core_db`: 9 lulus.
- Kompilasi Java 8 untuk model, API POS, dan helper pembelian: lulus.
- Kesesuaian salinan sumber Java `java/` dan `src/`: terverifikasi identik sebelum commit.

## Rollback

- Hentikan rollout bila simpan produk/pembelian gagal, hasil konversi stok tidak sesuai, atau sinkronisasi master UOM ditolak server.
- Kembalikan aplikasi ke rilis sebelumnya dan server ke revisi sebelum `r78484`.
- Jalankan `rollback_uom_kategori_pembelian_20260828.sql`. Skrip mempertahankan kolom audit/snapshot agar bukti transaksi tidak hilang.

## Artefak

Nama installer, ukuran, dan SHA-256 diisi setelah build bersih selesai.
