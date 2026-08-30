# Stok Opname Konsisten di Server dan Seluruh Kasir

Tanggal: 30 Agustus 2026

## Tujuan

Setelah hasil stok opname disimpan, angka stok pada server, master Produk, dan halaman Kasir/POS di semua perangkat harus mengikuti stok akhir yang sama. Kesalahan input dapat dibatalkan oleh admin atau supervisor tanpa menghapus jejak audit.

## Kontrak yang diterapkan

1. `so_simpan` menghitung ulang stok produk dalam transaksi database yang sama dan mengembalikan `produkId`, `stokSistem`, `stokFisik`, `selisih`, `stokAkhir`, dan `versiStok`.
2. Perangkat yang melakukan input langsung menambal kolom stok pada `produk_cache`. Jika server sedang tidak tersedia, stok fisik tetap dipakai secara lokal dan mutasi masuk antrean; respons server saat replay akan menggantinya dengan stok akhir otoritatif.
3. `so_perubahan_stok` menyediakan feed ringan berbasis cursor jurnal opname. Setiap perangkat aktif memeriksa perubahan setiap 15 detik dan hanya memperbarui produk yang berubah, bukan mengunduh ulang seluruh katalog.
4. Halaman Kasir dan Produk mendengarkan revisi cache sehingga kartu/list stok diperbarui tanpa memulai ulang aplikasi.
5. `so_batalkan` hanya boleh dipanggil admin atau supervisor toko. Pembatalan membuat jurnal kompensasi dengan penanda `[BATAL_SO:<id>]`; jurnal asli tidak dihapus.
6. Pembatalan wajib memiliki alasan minimal lima karakter, tidak dapat diterapkan pada jurnal pembatalan, idempoten bila tombol terkirim ulang, dan ditolak bila opname sudah diposting ke jurnal akuntansi.

## Urutan deploy

1. Deploy backend SVN lebih dahulu karena desktop baru memanggil `so_perubahan_stok` dan `so_batalkan`.
2. Uji `so_simpan`: stok fisik 12 harus menghasilkan `stokAkhir=12` dan master `produk.stok=12`.
3. Login pada dua perangkat di toko yang sama; perangkat kedua harus menampilkan 12 paling lambat sekitar 15 detik tanpa sinkron katalog penuh.
4. Login supervisor, batalkan opname dengan alasan yang jelas. Pastikan riwayat asal berstatus *Dibatalkan*, muncul baris *Jurnal pembatalan*, dan seluruh perangkat mengikuti stok koreksi.
5. Setelah backend lulus, publikasikan build desktop varian `albahjah`, `nahl`, dan `ebisnis`.

## Verifikasi pengembangan

- Perubahan backend sudah dicatat di SVN revisi `r78605`.
- Flutter analyzer tidak menemukan error baru pada perubahan ini; temuan yang tersisa merupakan lint/info lama di file lain.
- Sebanyak 40 pengujian kontrak local-first, retry server, dan paginasi cache lulus.
- Tiga class backend yang berubah berhasil dikompilasi terarah dengan Java 8.
- Kompilasi penuh 7.316 source sempat berhenti karena ruang drive habis saat menulis class, bukan karena error source. Keluaran Maven kemudian dibersihkan dan validasi terarah berhasil.

## Catatan operasional

Jika satu kasir belum berubah setelah 15–30 detik, periksa koneksi internet dan menu Sistem > Riwayat Sinkronisasi. Jangan mengulang stok opname yang sama hanya untuk menyegarkan layar. Begitu server dapat dihubungi, feed perubahan dan antrean lokal akan mencoba kembali secara otomatis.
