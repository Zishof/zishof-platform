# Runbook Koreksi Produk Tanpa Satuan

Tanggal: 29 Agustus 2026

Lingkup: POS Al-Bahjah, toko `1`

Tujuan: melengkapi satuan dasar dan satuan pembelian tanpa menebak data atau mengubah audit stok/HPP historis.

## Kapan runbook ini digunakan

Gunakan ketika produk tidak muncul pada pencarian bahan baku/UOM, konversi pembelian tidak dapat dihitung, atau laporan menunjukkan produk tanpa satuan.

Hasil audit produksi 29 Agustus 2026:

- 234 produk belum mempunyai satuan dasar.
- 229 produk masih aktif.
- 224 produk mempunyai stok bukan nol.
- 222 produk mempunyai riwayat penerimaan, mencakup 228 baris penerimaan.

Karena sebagian besar data masih aktif dan berdampak pada stok, satuan tidak boleh diisi otomatis berdasarkan nama produk.

## Berkas kerja

- `template-koreksi-produk-tanpa-satuan-v2-20260829.csv`: 234 produk, sudah diurutkan menurut prioritas dan mempunyai kolom keputusan admin. Enam baris memuat usulan dari kecocokan barcode/nama identik; usulan tetap wajib dikonfirmasi.
- `referensi-uom-20260829.csv`: 22 UOM yang saat ini tersedia beserta ID, kategori, tipe konversi, rasio, dan presisinya.
- `rencana-konsolidasi-uom-20260829.csv`: delapan kelompok nama UOM beserta seluruh ID legacy untuk diisi keputusan kategori canonical dan UOM reference.
- Salinan server berada di `/backup4/deployments/albahjah-uom-r78485-20260829-0125`.

Kolom yang harus diisi admin pada template:

- `pilih_satuan_dasar_id`: UOM yang dipakai untuk stok dan penjualan.
- `pilih_satuan_pembelian_id`: UOM saat PO/penerimaan. Isi sama dengan satuan dasar bila tidak ada kemasan pembelian berbeda.
- `kemasan_dan_rasio`: contoh `1 Dus = 24 Pcs`. Jangan hanya menulis `Dus` tanpa jumlah isi.
- `catatan_admin`: sumber keputusan, misalnya kemasan fisik, faktur pemasok, atau konfirmasi PIC toko.

Kolom `usulan_satuan_id_exact_match`, `dasar_usulan`, dan `sumber_produk_id` hanya merupakan alat bantu audit. Jangan menyalin usulan ke kolom keputusan sebelum produk sumber dan kemasan fisiknya diperiksa. Contoh produksi menunjukkan produk bernama botol dapat mempunyai pasangan nama identik yang memakai UOM `DUS`.

## Prasyarat

1. Gunakan akun admin/supervisor yang berhak mengubah master UOM dan produk.
2. Pastikan desktop minimal versi `1.34.03+161` dan server minimal SVN `r78485`.
3. Buka **Master Data → Satuan / UOM** dan **Master Data → Produk**.
4. Siapkan bukti kemasan atau faktur pemasok untuk menentukan rasio.

## Prosedur

### 1. Normalisasi master UOM

Master saat ini sengaja menempatkan setiap UOM lama pada kategori `LEGACY_<id>`. Walaupun beberapa nama sama, misalnya `Pcs`, `Pak`, `DUS`, `gram`, atau `LITER`, sistem tidak menganggapnya dapat saling dikonversi.

Untuk setiap kelompok yang akan digunakan:

1. Tentukan kategori bisnis yang benar, misalnya `UNIT`, `BERAT`, atau `VOLUME`.
2. Tentukan tepat satu UOM referensi dengan rasio `1`.
3. Masukkan UOM turunan hanya jika hubungan konversinya pasti.
4. Jangan menghubungkan UOM lintas dimensi, misalnya Liter ke Pcs, tanpa aturan produk/kemasan yang eksplisit.
5. Jika dua UOM bernama sama ternyata memang identik, konsolidasikan secara terencana melalui aplikasi. Jangan mengganti ID langsung di database.

### 2. Koreksi produk berdasarkan prioritas

Kerjakan template dengan urutan berikut:

1. `P1-Aktif-dan-Berdampak`: produk aktif yang mempunyai stok atau riwayat penerimaan.
2. `P2-Aktif`: produk aktif tanpa stok/riwayat saat ini.
3. `P3-Nonaktif`: produk nonaktif; tetap lengkapi bila akan diaktifkan kembali.

Untuk setiap produk:

1. Buka produk berdasarkan `id`, `kode`, atau `barcode` dari template.
2. Pilih **Satuan Dasar/Penjualan** dari searchbox UOM.
3. Pilih **Satuan Pembelian**.
4. Jika satuan pembelian berbeda, isi kemasan dan rasio berdasarkan bukti. Contoh: satuan dasar `Pcs`, satuan pembelian `Dus`, rasio `24`.
5. Simpan. Form harus tertutup setelah penyimpanan berhasil.
6. Tekan **Sinkronkan/Muat Ulang** sebelum menguji produk tersebut pada perangkat lain.

### 3. UAT per kelompok UOM

Minimal uji satu produk dari setiap kategori/rasio:

1. Buat penerimaan sebanyak `1` satuan pembelian.
2. Pastikan stok bertambah sebesar rasio dalam satuan dasar.
3. Pastikan harga beli per satuan dasar dihitung dari harga satuan pembelian dibagi rasio.
4. Pastikan Kasir menjual dalam satuan dasar; barcode kemasan, bila ada, menambahkan kuantitas sesuai isi kemasan.
5. Buka detail penerimaan dan pastikan satuan input, kuantitas input, faktor konversi, dan harga input tersimpan sebagai snapshot.

## Larangan

- Jangan mengisi satuan berdasarkan tebakan dari nama produk.
- Jangan menjalankan `UPDATE` massal langsung pada database.
- Jangan mengubah snapshot penerimaan lama agar terlihat lengkap.
- Jangan menggabungkan UOM hanya karena namanya sama; kategori dan rasio harus diperiksa.

## Jika terjadi kesalahan

- Belum ada transaksi baru: kembalikan master produk/UOM ke nilai yang telah diverifikasi, lalu sinkronkan ulang.
- Sudah ada transaksi baru: jangan mengubah payload atau snapshot transaksi. Hentikan penggunaan produk tersebut dan minta supervisor memeriksa stok, HPP, serta kebutuhan jurnal koreksi.
- Konversi ditolak server: baca pesan sebab dan tindakan pada aplikasi; perbaiki kategori, UOM referensi, atau rasio, lalu coba ulang sekali.
- Eskalasi ke tim backend bila pesan tidak menyebut produk, UOM, nilai yang ditolak, dan tindakan koreksi yang dapat dilakukan pengguna.

## Kriteria selesai

- Tidak ada lagi produk aktif tanpa satuan dasar.
- Seluruh produk aktif memiliki satuan pembelian.
- Setiap konversi mempunyai kategori sama, satu UOM referensi, rasio positif, dan presisi pembulatan valid.
- UAT penerimaan dan Kasir lulus untuk setiap pola konversi yang dipakai.
- Hasil keputusan admin dan bukti sumber disimpan bersama template koreksi.
