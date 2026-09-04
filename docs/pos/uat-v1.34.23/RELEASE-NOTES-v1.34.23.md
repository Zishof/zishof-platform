# eBisnis POS v1.34.23 - UAT Kantin, Posting, dan Laporan Keuangan

Tanggal rilis: 5 September 2026

Build aplikasi: `1.34.23+185`

Varian: eBisnis, Al-Bahjah, dan Nahl

## Ringkasan

Rilis ini menyelesaikan UAT end-to-end alur Kantin POS, Kulakan, Akuntansi, Jurnal Umum, dan Laporan Keuangan. Fokus utama rilis adalah keterlacakan status posting, kelengkapan sumber akun debit/kredit, volume data contoh yang representatif, serta tampilan laporan yang menggunakan seluruh lebar area kerja.

Hasil akhir UAT adalah lulus 100% pada ruang lingkup Kantin. Posting Penjualan, HPP, dan Kulakan tidak menyisakan dokumen tertunda; seluruh pemeriksaan master akun bernilai nol; 4.107 baris jurnal terposting tidak memiliki jurnal tidak seimbang; dan enam laporan keuangan berhasil dimuat dari server dengan data.

## Perubahan aplikasi

### Filter status pada seluruh halaman posting Kantin

Halaman Posting Penjualan, Posting HPP, dan Posting Kulakan sekarang menyediakan tiga pilihan yang konsisten:

1. **Semua** - menampilkan histori terposting dan dokumen yang belum diposting.
2. **Telah Diposting** - menampilkan histori yang sudah mempunyai nomor jurnal.
3. **Belum Diposting** - menampilkan dokumen siap maupun tertahan yang masih membutuhkan tindakan.

Setiap baris menampilkan status yang eksplisit. Histori terposting menampilkan nomor jurnal dan keterangan bahwa transaksi telah tercatat di buku besar. Dokumen yang belum siap menampilkan alasan pemetaan akun serta tombol koreksi master.

### Sumber akun dan tindakan koreksi

Panel penjelasan pada halaman posting menerangkan asal akun debit dan kredit. Pengguna tidak perlu menebak atau mengubah baris jurnal sementara. Tombol **Sesuaikan Akun Debet** dan **Sesuaikan Akun Kredit** membuka master sumber yang relevan. Setelah master disimpan, pratinjau dihitung ulang oleh server.

Baseline akun Kantin yang dipakai pada UAT:

| Proses | Debit | Kredit |
|---|---|---|
| Penjualan tunai | 111.101 Kas Yayasan | 410.900 Pendapatan Penjualan Toko |
| Penjualan kredit | 131.300 Piutang Usaha Toko | 410.900 Pendapatan Penjualan Toko |
| HPP | 510.900 Beban Pokok Penjualan Toko | 151.200 Persediaan Barang Lainnya |
| Kulakan tunai | 151.200 Persediaan Barang Lainnya | 111.101 Kas Yayasan |
| Kulakan termin | 151.200 Persediaan Barang Lainnya | 310.600 Utang Usaha Toko |

Kode akun tersebut dipilih dari daftar akun yang diberikan untuk kebutuhan UAT dan telah diverifikasi sebagai akun daun aktif.

### Laporan memenuhi lebar layar

Laporan berbasis jurnal sekarang menggunakan ruang horizontal sampai sisi kanan sehingga deskripsi akun, referensi, nilai, dan tindakan dapat dibaca tanpa menumpuk di sisi kiri. Bukti UAT mencakup:

- Laba Rugi;
- Neraca;
- Arus Kas;
- Keseluruhan Jurnal;
- Buku Besar; dan
- Neraca Saldo.

Setiap laporan diuji pada resolusi area kerja 2560 x 1392, menggunakan data live server dan periode 1-30 September 2026.

## Perubahan API/server yang telah dideploy

Server mengembalikan histori posting bersama nomor jurnal, label status, dan penanda `sudahDiposting`. Normalisasi hasil query Posting Penjualan dan Posting HPP diperkuat agar nilai skalar PostgreSQL dibaca sebelum `ResultSet` ditutup. Perubahan ini menghilangkan kegagalan `This ResultSet is closed` yang ditemukan pada pengujian sebelumnya.

Endpoint posting mempertahankan kontrak lama untuk draf sekaligus menambahkan histori terposting. Karena perubahan server terbaru sudah dideploy dan seluruh UAT runtime lulus, tidak diperlukan deploy server tambahan untuk ruang lingkup rilis ini.

## Data dan hasil UAT

| Pemeriksaan | Aktual | Hasil |
|---|---:|---|
| Posting Penjualan | 403 terposting; belum posting 0 | LULUS |
| Posting HPP | 104 terposting; belum posting 0 | LULUS |
| Kulakan | 407 faktur; 402 terposting; belum posting 0 | LULUS |
| Baris jurnal terposting | 4.107 | LULUS |
| Jurnal tidak seimbang | 0 | LULUS |
| Master akun wajib kosong | 0 | LULUS |
| Laporan dengan data | 6 dari 6 | LULUS |
| Pengujian regresi Flutter | 762 dari 762 | LULUS |

UAT volume lintas workflow juga memverifikasi respons API untuk Penjualan, Kulakan, Pengadaan, dan Keuangan. Tidak ada endpoint yang gagal pada audit akhir.

## Jurnal Umum

Panduan baru menjelaskan pembuatan jurnal manual dari pencarian bukti, pengisian tanggal dan keterangan, pemilihan akun daun, pengisian debit/kredit, pemeriksaan keseimbangan, penyimpanan draf, review, posting, hingga penelusuran nomor jurnal pada Buku Besar.

Jenis jurnal yang didokumentasikan meliputi jurnal operasional, penyesuaian, akrual, deferral, penyusutan, pembalik, koreksi, saldo awal, dan penutup. Penjualan, HPP, serta Kulakan tetap harus menggunakan proses posting otomatis agar tidak terjadi pencatatan ganda.

## Dokumentasi rilis

Rilis menyertakan tiga format dokumentasi baru dan tidak menimpa manual versi sebelumnya:

- Word: manual pengguna dan UAT 70 halaman;
- PDF: hasil ekspor Word yang telah diperiksa visual;
- PowerPoint: presentasi eksekutif dan operasional 20 slide.

Manual menggunakan 22 tangkapan layar dan 66 diagram khusus layar, terdiri atas use case, flowchart, serta aliran data/ERD ringkas. Narasi pada setiap layar disesuaikan dengan fungsi dan bukti yang benar-benar terlihat; tidak menggunakan paragraf generik berulang.

## Build dan verifikasi

Ketiga varian dibangun dari source dan versi yang sama. Proses build memverifikasi keberadaan serta hash model wajah sebelum kompilasi. Paket Android dan Windows disertai berkas SHA-256.

Lingkungan build ini tidak memiliki keystore Android produksi atau sertifikat Authenticode Windows. Oleh karena itu paket yang dilampirkan pada rilis ini ditujukan untuk **UAT internal**:

- APK ditandatangani menggunakan sertifikat Android Debug;
- installer Windows tidak memiliki Authenticode.

Jangan mendistribusikan paket ini sebagai paket produksi publik. Untuk rilis produksi, build ulang commit/tag yang sama menggunakan keystore Android produksi dan sertifikat Authenticode organisasi.

## Pemeriksaan kualitas

- `flutter test`: 762 lulus, 0 gagal.
- Pengujian kontrak filter dan status posting: lulus.
- UAT runtime akun Kantin: lulus; seluruh akun wajib lengkap.
- Audit jurnal: 4.107 baris; tidak seimbang 0.
- Audit volume workflow: seluruh endpoint yang diuji berhasil.
- UAT screenshot Posting Penjualan/HPP/Kulakan: lulus dan menampilkan lebih dari 100 histori.
- UAT screenshot enam laporan: lulus, live, dan full-width.
- Pemeriksaan visual Word/PDF: 70 halaman, tidak ada halaman kosong.
- Pemeriksaan PowerPoint: 20 slide, tidak ada overflow.

Analisis statis tidak menemukan error atau warning. Terdapat 50 saran gaya tingkat `info` pada kode lama di luar perubahan rilis; saran tersebut tidak memengaruhi build atau hasil UAT.

## Cara verifikasi setelah instalasi

1. Jalankan aplikasi dan pilih toko Kantin yang benar.
2. Buka Akuntansi lalu Posting Penjualan, Posting HPP, dan Posting Kulakan.
3. Tetapkan periode 1-30 September 2026 dan muat pratinjau.
4. Bandingkan jumlah pada filter Semua, Telah Diposting, dan Belum Diposting.
5. Ambil sampel nomor referensi dan telusuri nomor jurnalnya pada Keseluruhan Jurnal.
6. Periksa Buku Besar untuk akun Kas, Piutang, Persediaan, Utang, Pendapatan, dan HPP.
7. Tampilkan Laba Rugi, Neraca, Arus Kas, Keseluruhan Jurnal, Buku Besar, serta Neraca Saldo.
8. Pastikan laporan menggunakan seluruh lebar layar dan tidak ada kolom penting terpotong.

## Rollback

Rollback aplikasi dilakukan dengan memasang kembali paket versi sebelumnya yang telah disimpan. Jika server perlu dikembalikan, pulihkan source server ke revisi sebelum perubahan histori posting, kompilasi menggunakan target Ant yang sama, lalu deploy melalui prosedur server organisasi. Data jurnal yang sudah diposting tidak boleh dihapus sebagai bagian rollback aplikasi; gunakan prosedur pembalik/koreksi yang disetujui Akuntansi.
