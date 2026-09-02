# Perbaikan Laporan Piutang Kasbon dan Rincian Produk

Tanggal verifikasi: 3 September 2026

## Ringkasan masalah

Laporan **Daftar Saldo Piutang Customer** sebelumnya menentukan piutang dari selisih total nota dengan kolom ringkasan `bayar_tunai` dan `bayar_non_tunai`. Pada transaksi lama atau transaksi dengan metode tertentu, kedua kolom ringkasan tersebut dapat bernilai nol walaupun pembayaran sebenarnya memakai Voucher Pejuang atau QRIS. Akibatnya seluruh nilai nota salah masuk sebagai piutang.

Sampel Fauzi Rahman membuktikan pola ini secara tepat:

- Voucher Pejuang Rp39.000
- QRIS BSI Rp66.000
- Voucher Pejuang Rp157.000
- Total yang keliru tampil sebagai piutang: **Rp262.000**

Masalah kedua terdapat pada drill-down laporan. Kolom `Kode` pada laporan piutang adalah kode pelanggan, tetapi sebelumnya dibaca sebagai kode produk. Karena itu rincian transaksi dan produk dapat kosong atau tidak sesuai dengan angka yang diklik.

## Perbaikan yang diterapkan

### 1. Klasifikasi piutang berbasis metode pembayaran

Sumber laporan piutang sekarang membaca sampai lima slot metode pembayaran pada setiap nota. Suatu nilai hanya diklasifikasikan sebagai piutang bila master metode pembayaran:

1. ditandai `masuk_sebagai_hutang = true`; dan
2. kode atau nama metode mengandung kata `Kasbon`.

Pemeriksaan ganda tersebut bersifat *fail-closed*. Voucher, QRIS, Tunai, Transfer, dan metode non-Kasbon lain tidak masuk laporan piutang, termasuk bila konfigurasi lama pada master metode pembayaran pernah keliru.

Jenis piutang dinormalisasi menjadi:

- Kasbon Divisi;
- Kasbon Pejuang;
- Kasbon Operasional; atau
- nama metode Kasbon lain sebagai fallback.

### 2. Nilai piutang split payment

Untuk transaksi dengan beberapa metode pembayaran, hanya nominal slot Kasbon yang menjadi piutang. Contoh: pembayaran Rp100.000 terdiri dari QRIS Rp60.000 dan Kasbon Pejuang Rp40.000, maka laporan piutang mencatat **Rp40.000**, bukan Rp100.000.

### 3. Rincian faktur dan produk

Angka jumlah faktur maupun saldo piutang tetap dapat diklik. Popup rincian kini menampilkan:

- waktu transaksi;
- nomor nota;
- kasir;
- pelanggan;
- produk;
- metode pembayaran lengkap pada faktur, termasuk transaksi campuran;
- jenis piutang;
- nilai piutang per faktur;
- kuantitas;
- harga;
- total nilai per baris produk; dan
- total piutang unik per faktur.

Total piutang dihitung satu kali per faktur, sehingga faktur dengan banyak produk tidak menggandakan nilai piutang.

### 4. Konsistensi semua laporan terkait

Sumber Kasbon yang sama dipakai pada:

- Daftar Saldo Piutang Customer;
- Faktur Kasbon/Piutang;
- Umur Piutang;
- Sisa Kredit;
- Piutang Usaha pada Neraca;
- popup rincian pada POS Desktop; dan
- popup rincian pada laporan web/ZK.

Baris detail penjualan yang sudah tidak aktif juga tidak ikut dihitung.

## Batasan model data lama

Rincian per faktur menampilkan nominal Kasbon asli pada transaksi. Pembayaran/cicilan hutang lama disimpan sebagai mutasi saldo anggota dan tidak dialokasikan ke nomor faktur tertentu. Karena itu rekonsiliasi pelunasan tetap harus dilihat bersama Buku Besar/Mutasi Hutang; sistem tidak menebak faktur mana yang dilunasi bila datanya memang tidak memiliki alokasi faktur.

Tidak ada transaksi historis yang dihapus atau diubah oleh perbaikan ini.

## Komponen yang perlu dipasang

Perbaikan terdiri dari dua sisi dan keduanya perlu dipasang agar hasil lengkap terlihat:

1. **Server AIS** — wajib untuk memperbaiki klasifikasi dan angka laporan. Deploy class backend dan JSP terbaru, kemudian restart Tomcat/service aplikasi.
2. **POS Desktop** — wajib untuk menampilkan kolom Jenis Piutang, Piutang Faktur, rincian produk, dan total piutang unik pada popup desktop. Build dan distribusikan installer terbaru setelah source seluruh sesi sudah digabung.

Server baru tetap memperbaiki angka laporan web walaupun installer desktop belum diperbarui, tetapi tampilan rinci desktop baru tersedia setelah aplikasi desktop diperbarui.

## Langkah deploy

1. Pastikan seluruh perubahan dari sesi lain sudah selesai dan tidak ada proses build/commit yang masih menulis source yang sama.
2. Ambil revisi server terbaru dan pastikan file pada pohon `src/main/src` serta mirror `src/main/java` identik.
3. Jalankan kompilasi server dan self-test SQL laporan.
4. Deploy class backend dan dua JSP laporan terbaru ke lingkungan tujuan.
5. Restart Tomcat/service AIS dan pastikan startup selesai tanpa error.
6. Build POS Desktop dari source terbaru untuk varian yang digunakan pengguna.
7. Pasang installer pada satu komputer UAT terlebih dahulu.
8. Login, pilih toko yang benar, tekan **Sinkronkan**, lalu **Muat Ulang**.
9. Laksanakan seluruh skenario UAT di bawah sebelum distribusi luas.

## Panduan UAT rinci

Gunakan pelanggan uji dan rentang tanggal pendek agar hasil mudah direkonsiliasi.

### A. Voucher Pejuang murni

1. Buat transaksi dengan pelanggan/member.
2. Pilih pembayaran Voucher Pejuang seluruhnya.
3. Selesaikan transaksi.
4. Pastikan nota muncul di Riwayat Penjualan.
5. Pastikan pemotongan muncul di Mutasi Voucher.
6. Buka Daftar Saldo Piutang Customer pada tanggal transaksi.
7. Pastikan nota dan nilainya **tidak** masuk piutang.

### B. QRIS murni

1. Buat transaksi dengan metode QRIS seluruhnya.
2. Pastikan nota muncul di Riwayat Penjualan/rekap pembayaran.
3. Pastikan nota dan nilainya **tidak** masuk laporan piutang.

### C. Kasbon Pejuang

1. Buat transaksi berisi sedikitnya dua produk.
2. Pilih metode Kasbon Pejuang.
3. Buka Daftar Saldo Piutang Customer.
4. Pastikan pelanggan, satu faktur, dan nilai Kasbon muncul.
5. Klik jumlah faktur atau saldo piutang.
6. Pastikan kedua produk, qty, harga, total produk, nomor nota, dan label **Kasbon Pejuang** tampil.
7. Pastikan total piutang hanya dihitung sekali walaupun faktur memiliki dua produk.

### D. Kasbon Divisi

Ulangi skenario C dengan metode Kasbon Divisi dan pastikan labelnya **Kasbon Divisi**.

### E. Split payment

1. Buat transaksi Rp100.000.
2. Bayar QRIS Rp60.000 dan Kasbon Pejuang Rp40.000.
3. Pastikan laporan piutang hanya menampilkan Rp40.000.
4. Pastikan popup tetap menampilkan semua produk pada faktur tersebut.

### F. Regresi sampel Fauzi Rahman

1. Pilih rentang 1 Agustus–2 September 2026.
2. Cari Fauzi Rahman/kode `20250506172`.
3. Cocokkan tiga transaksi Rp39.000, Rp66.000, dan Rp157.000 pada Riwayat Penjualan.
4. Pastikan transaksi Voucher Pejuang dan QRIS tersebut tidak lagi membentuk piutang Rp262.000.
5. Bila masih ada saldo Fauzi, buka rinciannya dan pastikan hanya berasal dari transaksi Kasbon yang nyata.

### G. Ekspor dan lintas toko

1. Ulangi filter untuk satu toko, lalu Semua Toko bila pengguna berizin.
2. Bandingkan angka layar dengan PDF dan Excel.
3. Pastikan jenis piutang ikut terbaca dan total per toko tidak bercampur.

## Bukti verifikasi teknis

- Tes fokus fitur piutang: lulus.
- Seluruh tes Flutter POS: **730 tes lulus**.
- Kompilasi terarah class Java yang berubah: lulus.
- Self-test SQL laporan server: **16 dari 16 pemeriksaan lulus**.
- `flutter analyze`: tidak menemukan error; terdapat info lint lama di file lain.
- Kompilasi Maven server penuh: **BUILD SUCCESS**.

## Kriteria rollback

Hentikan distribusi dan kembalikan paket sebelumnya bila salah satu kondisi berikut muncul pada UAT:

- transaksi Kasbon tidak muncul sama sekali;
- Voucher/QRIS masih menambah piutang;
- split payment memasukkan total nota, bukan porsi Kasbon;
- nilai piutang berlipat sesuai jumlah produk;
- laporan satu toko mencampur transaksi toko lain; atau
- startup server menghasilkan error class/JSP baru.

## Draf WhatsApp setelah server dan POS Desktop benar-benar dipasang

> Assalamu'alaikum warahmatullahi wabarakatuh.
>
> Bapak/Ibu, terkait laporan **Daftar Saldo Piutang Customer**, kendalanya sudah kami analisis dan perbaikannya sudah dipasang pada server serta POS Desktop terbaru.
>
> Penyebabnya adalah laporan versi sebelumnya membaca piutang dari kolom ringkasan pembayaran pada header transaksi. Pada sebagian transaksi lama, kolom tersebut kosong/nol walaupun metode pembayaran sebenarnya adalah Voucher Pejuang atau QRIS. Akibatnya nilai transaksi non-Kasbon ikut dianggap sebagai piutang. Pada sampel Bapak Fauzi Rahman, tiga transaksi sebesar Rp39.000, Rp66.000, dan Rp157.000 berjumlah tepat Rp262.000; transaksi tersebut memakai Voucher Pejuang/QRIS sehingga seharusnya tidak masuk piutang.
>
> Sekarang klasifikasi sudah diperketat. Laporan piutang hanya mengambil nominal dari metode pembayaran yang benar-benar berjenis **Kasbon**, yaitu antara lain Kasbon Pejuang, Kasbon Divisi, atau Kasbon Operasional. Voucher Pejuang, QRIS, Tunai, dan Transfer tidak lagi masuk laporan piutang. Bila satu transaksi memakai pembayaran campuran, misalnya sebagian QRIS dan sebagian Kasbon, yang dicatat sebagai piutang hanya bagian Kasbonnya.
>
> Rinciannya juga sudah ditambahkan. Angka jumlah faktur atau saldo pada daftar piutang dapat diklik untuk melihat nomor nota, tanggal/waktu, kasir, pelanggan, metode pembayaran lengkap, jenis piutang, nilai piutang per faktur, nama-nama produk, jumlah barang, harga, dan total produk. Untuk pembayaran campuran, seluruh nama metode terlihat sehingga bagian Kasbon dapat diperiksa langsung. Untuk satu faktur yang berisi beberapa produk, nilai piutangnya tetap dihitung satu kali sehingga tidak menjadi berlipat.
>
> Mohon dilakukan pengecekan dengan langkah berikut:
>
> 1. Tutup aplikasi POS Desktop lama, pasang versi terbaru, lalu buka kembali.
> 2. Login dan pastikan toko yang dipilih sudah benar.
> 3. Tekan **Sinkronkan**, tunggu sampai selesai, lalu tekan **Muat Ulang**.
> 4. Buka **Laporan → Daftar Saldo Piutang Customer**.
> 5. Pilih tanggal 1 Agustus sampai 2 September 2026, lalu cari **Fauzi Rahman** atau kode **20250506172**.
> 6. Pastikan transaksi Voucher Pejuang Rp39.000 dan Rp157.000 serta QRIS Rp66.000 tidak lagi membentuk saldo piutang Rp262.000.
> 7. Bila masih ada saldo atas nama Fauzi Rahman, silakan klik jumlah faktur/saldonya. Saldo yang tersisa semestinya hanya berasal dari transaksi Kasbon yang nyata, dan rincian produknya akan terlihat di popup.
> 8. Mohon uji satu transaksi Kasbon Pejuang dan satu Kasbon Divisi. Pastikan masing-masing masuk dengan label yang tepat dan semua produknya muncul.
> 9. Mohon uji satu transaksi Voucher Pejuang dan satu QRIS. Keduanya harus tetap tercatat pada Riwayat Penjualan, tetapi tidak masuk laporan piutang. Voucher tetap dapat diperiksa pada Mutasi Voucher.
> 10. Jika memakai pembayaran campuran, pastikan laporan hanya mencatat nominal bagian Kasbon.
>
> Catatan: perbaikan ini tidak menghapus maupun mengubah transaksi historis. Rincian faktur menampilkan nilai Kasbon asli pada saat transaksi. Pembayaran/cicilan hutang lama tetap dapat direkonsiliasi melalui Buku Besar/Mutasi Hutang karena pada data lama pembayaran tersebut tidak dialokasikan ke nomor faktur tertentu.
>
> Apabila masih ada perbedaan, mohon kirimkan nama pelanggan, nomor nota, tanggal/jam transaksi, toko, metode pembayaran, nominal tiap metode, dan tangkapan layar rincian yang muncul. Dengan data tersebut kami dapat menelusuri transaksi yang tepat tanpa mengubah data lainnya.
>
> Terima kasih. Wassalamu'alaikum warahmatullahi wabarakatuh.
