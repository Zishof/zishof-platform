# Runbook UAT POS Al-Bahjah 1.34.20

## Status dan tujuan

Dokumen ini menjadi panduan UAT internal untuk dua kebutuhan berikut:

1. koreksi transaksi selesai dari Detail Riwayat Penjualan; dan
2. rincian produk terjual pada laporan **Penjualan Barang Per Pemasok**.

Status saat dokumen dibuat: perubahan masih lokal untuk UAT. Belum diunggah ke GitHub, belum dibuatkan rilis, dan belum boleh dianggap sudah terpasang di server/komputer toko. Publikasi hanya dilakukan setelah UAT Al-Bahjah selesai dan ada izin pengguna.

## Makna pesan dan screenshot pengguna

### “Belum bisa mengubah metode harga” pada Detail Riwayat Penjualan

Screenshot tersebut bukan menunjukkan aplikasi rusak. Panel pada screenshot menyatakan kebijakan koreksi transaksi untuk toko itu belum aktif. Tombol edit memang disembunyikan oleh server ketika salah satu gerbang keamanan tidak terpenuhi.

Istilah “metode harga” perlu dikonfirmasi karena ada dua hal berbeda:

- Jika yang dimaksud **metode pembayaran** (Tunai, Transfer, QRIS, dan sebagainya), nilainya dapat dikoreksi setelah kebijakan dan hak akses terpenuhi, selama transaksi belum posting dan belum memiliki retur. Server tetap memeriksa aturan member, batas transaksi, batas hutang, serta keamanan saldo/deposit.
- Jika yang dimaksud **harga barang**, harga satuan pada transaksi selesai tidak dapat diketik/diubah langsung. Form menampilkannya sebagai informasi. Baris lama mempertahankan harga transaksi yang tersimpan; produk yang ditambahkan memakai harga master saat ini. Harga untuk transaksi berikutnya diubah melalui master/aturan harga. Pembatasan ini menjaga jejak audit dan mencegah perubahan nilai nota tanpa sumber harga yang sah.

### Permintaan laporan item yang terjual per pemasok

Laporan sebelumnya terlalu agregat sehingga pengguna hanya melihat pemasok dan total. Laporan bersama kini dirinci sampai produk dan satuan yang terjual, sehingga dapat menjawab barang apa yang terjual dari tiap pemasok.

## Akar masalah

1. Hak edit bukan hanya hak menu. Efektivitas koreksi ditentukan bersama oleh kebijakan global/per toko, peran pengguna, dan status transaksi.
2. Pesan pada dialog lama menyebut “audit JSON”, padahal implementasi sebenarnya memakai revisi Hibernate Envers dan alasan pada keterangan header.
3. Jalur koreksi lama belum menjalankan kembali semua validasi finansial checkout saat metode/total pembayaran berubah.
4. Query laporan pemasok sebelumnya berhenti pada agregat pemasok dan belum memperlihatkan identitas produk/UOM yang terjual.

## Perbaikan yang tersedia untuk UAT

### Koreksi transaksi

- Detail transaksi mengembalikan status kebijakan global, kebijakan toko, hak aktivasi, toko transaksi, dan keputusan apakah transaksi boleh diedit.
- Admin/supervisor yang memenuhi syarat mendapat tombol cepat **Aktifkan Koreksi Toko** saat global dan toko sama-sama nonaktif.
- Aktivasi cepat bersifat online-only dan dikunci oleh server ke toko transaksi; klien tidak dapat memilih toko lain melalui payload.
- Koreksi tetap atomik, mewajibkan alasan minimal lima karakter, menghitung ulang total dan stok, serta menyimpan riwayat audit sebelum/sesudah beserta alasan.
- Server menolak transaksi yang sudah diposting atau sudah memiliki retur.
- Server memvalidasi kembali metode pembayaran terhadap tipe/jenis member.
- Komposisi split-payment lama tetap dipertahankan ketika pengguna mengoreksi tanggal, kasir, produk, atau qty tanpa menyentuh dropdown metode pembayaran. Split hanya diratakan ke satu metode bila pengguna benar-benar memilih metode baru.
- Kasbon, voucher, atau metode wajib-member ditolak bila transaksi tidak mempunyai member/PIC.
- Batas transaksi harian, mingguan, dan bulanan diperiksa kembali dengan mengecualikan nilai nota lama agar tidak dihitung dua kali.
- Batas hutang dihitung sebagai `hutang berjalan - bagian hutang nota lama + bagian hutang hasil koreksi`.
- Koreksi tidak boleh menambah pemotongan saldo/deposit. Gunakan pembatalan/retur resmi dan transaksi baru agar saldo divalidasi ulang oleh alur checkout.
- Teks dialog kini menyebut mekanisme audit secara faktual, bukan “audit JSON”.

Tiga gerbang utama edit:

1. kebijakan koreksi efektif: global aktif, atau konfigurasi toko transaksi aktif;
2. pengguna adalah admin/supervisor atau mempunyai role **Supervisor** yang diakui server; dan
3. transaksi belum posting ke jurnal serta belum memiliki retur.

### Laporan Penjualan Barang Per Pemasok

Query laporan bersama Desktop, Android, PDF/Excel, dan ZK kini memuat:

- Pemasok;
- Kode Produk;
- Produk Terjual;
- Satuan Terjual;
- Qty UOM;
- Qty Dasar; dan
- Total Penjualan.

Nilai penjualan memakai total final baris transaksi, dengan fallback untuk data lama, agar harga Pack/grosir tidak dihitung ulang secara keliru. Kode/nama snapshot baris transaksi dipakai ketika master produk sudah tidak tersedia.

Keterbatasan yang harus disampaikan: pemasok masih ditentukan dari histori **pengadaan terakhir** produk, bukan dari batch/lot historis yang benar-benar keluar ketika transaksi terjadi. Label **Tanpa Pemasok** berarti produk tidak memiliki histori pengadaan dengan nama pemasok yang dapat dipakai.

## Cara membuka fitur

### Aktivasi cepat koreksi toko

1. Masuk sebagai admin/supervisor.
2. Buka **Riwayat Penjualan**.
3. Buka detail transaksi dummy yang sudah tersinkron ke server.
4. Jika kebijakan global dan toko belum aktif, tekan **Aktifkan Koreksi Toko**.
5. Baca konfirmasi, lalu tekan **Aktifkan untuk Toko Ini**.
6. Aplikasi meminta server mengaktifkan toko transaksi dan membuka ulang detail.
7. Tekan **Edit Transaksi** dan masukkan alasan koreksi.

### Jalur konfigurasi manual

- Kebijakan global: **Konfigurasi > Keamanan & Koreksi Transaksi > Izinkan Edit Transaksi dari Riwayat Penjualan**.
- Kebijakan per toko: buka profil toko pada Konfigurasi, lalu **Keamanan & Koreksi Transaksi Toko > Izinkan Edit Transaksi dari Riwayat Penjualan**.
- Bila global aktif, seluruh toko mengikuti global. Bila global nonaktif, keputusan mengikuti nilai toko masing-masing.

### Laporan pemasok

1. Buka menu **Laporan**.
2. Pilih kategori **Penjualan**, atau cari kata `pemasok`.
3. Buka **Penjualan Barang Per Pemasok**.
4. Pilih periode dan filter toko/produk bila tersedia bagi pengguna.
5. Jalankan laporan.
6. Periksa kelompok pemasok dan rincian Kode Produk, Produk Terjual, Satuan Terjual, Qty UOM, Qty Dasar, serta Total Penjualan.
7. Gunakan aksi PDF atau Excel pada layar laporan untuk memeriksa hasil ekspor.

## Kebutuhan deployment

| Kemampuan | Update server | Update client 1.34.20 |
|---|---:|---:|
| Tombol cepat Aktivasi Koreksi Toko | Wajib | Wajib |
| Validasi member, batas transaksi, hutang, dan deposit saat koreksi | Wajib | Tidak cukup tanpa server |
| Rincian produk laporan di Desktop/Android | Wajib | Client generik dapat membaca kolom server; 1.34.20 direkomendasikan untuk UAT terpadu |
| Rincian laporan PDF/Excel/ZK | Wajib | Tidak untuk ZK; PDF dibuat server, Excel mengikuti data layar Flutter |
| Teks audit yang diperbaiki pada dialog | Tidak | Wajib |

Jangan menguji tombol baru terhadap server lama: endpoint aktivasi dan validasi koreksi berada di backend. Jangan menyimpulkan fitur sudah diterapkan ke toko hanya karena installer lokal berhasil dibangun.

## Prasyarat UAT

- Gunakan server UAT/staging atau backup database yang dapat dipulihkan.
- Gunakan akun admin/supervisor khusus UAT.
- Siapkan satu toko uji dengan kebijakan global nonaktif dan kebijakan toko nonaktif.
- Siapkan transaksi dummy yang belum posting dan belum memiliki retur.
- Catat stok awal setiap produk dummy, total nota, metode pembayaran, member, serta saldo hutang/deposit sebelum tes.
- Jangan memakai transaksi produksi sensitif atau transaksi pelanggan riil.

## Skenario UAT rinci

### A. Gerbang kebijakan dan hak akses

1. Masuk dengan kasir biasa dan buka transaksi dummy. Pastikan tombol edit/aktivasi cepat tidak tersedia.
2. Masuk sebagai supervisor/admin. Dengan global dan toko nonaktif, pastikan detail menjelaskan kebijakan nonaktif dan menampilkan **Aktifkan Koreksi Toko**.
3. Batalkan dialog konfirmasi. Pastikan kebijakan tidak berubah.
4. Ulangi dan setujui. Pastikan ada pesan sukses, detail dibuka ulang, dan **Edit Transaksi** tersedia.
5. Putuskan koneksi lalu coba aktivasi pada toko uji lain. Pastikan aplikasi tidak menampilkan sukses lokal palsu.

### B. Koreksi aman transaksi dummy

1. Ubah tanggal/jam ke waktu lampau yang valid, kasir, metode pembayaran biasa, jumlah produk, lalu isi alasan yang jelas.
2. Simpan dan pastikan total serta stok dihitung ulang.
3. Buka lagi detail dan Riwayat Audit. Pastikan nilai sebelum/sesudah, pelaku, waktu, dan alasan dapat ditelusuri.
4. Periksa nota/laporan transaksi agar metode pembayaran dan total konsisten.
5. Pastikan harga satuan hanya tampil sebagai informasi dan tidak memiliki input edit bebas.
6. Tambahkan produk baru dan pastikan server memakai harga master, bukan angka `harga` yang dapat direkayasa dari payload klien.

### C. Skenario penolakan finansial

1. Pada transaksi tanpa member, pilih Kasbon/voucher/metode wajib-member. Harus ditolak dengan pesan meminta member/PIC.
2. Pada transaksi member, pilih metode yang dilarang oleh jenis/tipe member. Harus ditolak.
3. Naikkan total hingga melewati batas harian/mingguan/bulanan member. Harus ditolak tanpa perubahan nota/stok.
4. Ubah ke Kasbon atau naikkan total Kasbon hingga proyeksi hutang melewati batas. Harus ditolak; nilai nota lama tidak boleh terhitung dua kali.
5. Coba menambah nilai pemotongan saldo/deposit. Harus ditolak dan mengarahkan ke pembatalan/retur resmi serta transaksi baru.
6. Setelah setiap penolakan, muat ulang transaksi dan stok untuk memastikan rollback utuh.

### D. Status transaksi yang tidak boleh dikoreksi

1. Coba transaksi dummy yang sudah posting. Tombol edit harus tidak tersedia atau server menolak.
2. Coba transaksi dummy yang mempunyai retur. Tombol edit harus tidak tersedia atau server menolak.
3. Coba transaksi milik toko lain dari akun yang terikat toko. Server harus menolak.

### E. Laporan pemasok lintas kanal

1. Buat transaksi dummy yang mencakup produk satuan dasar dan Pack/grosir.
2. Jalankan **Penjualan Barang Per Pemasok** untuk periode transaksi.
3. Cocokkan qty UOM, qty dasar, dan total final dengan nota.
4. Uji produk yang master-nya sudah tidak tersedia pada data salinan UAT; label snapshot transaksi harus tetap muncul.
5. Uji produk tanpa histori pengadaan bernama; baris harus berada di **Tanpa Pemasok**.
6. Ekspor PDF dan Excel, lalu cocokkan jumlah kolom/baris dan total dengan tampilan.
7. Ulangi pada Desktop, Android, dan ZK yang menunjuk server UAT yang sama.
8. Catat bahwa kesesuaian pemasok pada tes ini mengikuti pengadaan terakhir; jangan menilainya sebagai pelacakan batch/lot historis.

## Kriteria lulus

- Tidak ada edit tanpa tiga gerbang keamanan.
- Aktivasi cepat hanya mengubah toko transaksi dan gagal secara jelas saat offline.
- Semua koreksi finansial berisiko ditolak oleh server, bukan hanya UI.
- Koreksi yang valid mengubah total/stok secara atomik dan meninggalkan audit yang dapat ditelusuri.
- Laporan layar, PDF, Excel, dan ZK memperlihatkan produk/UOM dengan angka yang konsisten.
- Tidak ada data produksi sensitif yang dipakai selama UAT.

## Validasi teknis lokal

- Targeted Flutter tests koreksi + laporan pemasok + posting akun: **12/12 lulus**.
- Flutter analyze dengan `--no-fatal-infos`: **exit 0**; tersisa 50 lint level `info` lama, tanpa warning/error.
- Maven incremental compile: **BUILD SUCCESS**, 35 source dikompilasi.
- `KantinKoreksiTransaksiSelfTest`: **lulus semua 9 aturan**.
- `LaporanKantinSqlSelfTest`: **lulus semua 18 aturan**.
- Build Windows Al-Bahjah 1.34.20 unsigned/UAT: **berhasil**.
- Installer lokal: `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\release-artifacts\semua-varian\1.34.20\Al-Bahjah-POS-Setup-1.34.20.exe` (85.946.604 byte; SHA-256 `04E2FCE109CFEA88212D295414EF249470C50F7715B26B61EDA76407FFF3BC5E`).
- Smoke-run executable lokal: **berhasil**, proses `ebisnis_albahjah` tetap hidup dan jendela berjudul **Al-Bahjah POS** tampil. Executable yang dijalankan: `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\build\windows\x64\runner\Release\ebisnis_albahjah.exe` (SHA-256 `31E029F14FA24807EBDBCB5E6002358F5562150288FC6B7516E31F9AF37E3F42`).

## Rollback

1. Hentikan UAT dan nonaktifkan kebijakan global/per toko untuk segera menutup jalur edit.
2. Tutup aplikasi UAT dan jalankan kembali installer versi stabil sebelumnya pada perangkat UAT.
3. Kembalikan deployment backend ke WAR/classes versi stabil sebelumnya melalui prosedur server yang berlaku, lalu restart aplikasi server secara terkendali.
4. Verifikasi endpoint detail transaksi kembali pada versi stabil dan jalankan laporan periode pendek.
5. Bila koreksi dummy sudah tersimpan, jangan menghapus baris database secara manual. Gunakan retur/pembatalan resmi atau pulihkan database UAT dari backup sesuai keputusan penanggung jawab.
6. Simpan log, alasan rollback, versi client/server, dan daftar transaksi dummy yang terdampak.

Perubahan ini tidak memerlukan migrasi schema database baru; rollback berfokus pada binary/config dan data dummy hasil UAT.

## Balasan WA siap salin

Assalamu’alaikum. Kami sudah cek screenshot dan permintaan laporannya.

Untuk screenshot “belum bisa mengubah metode harga”, itu bukan error aplikasi. Pesan tersebut berarti kebijakan koreksi transaksi untuk toko itu masih nonaktif. Edit transaksi selesai memang dijaga oleh 3 hal: (1) kebijakan global atau kebijakan toko harus aktif, (2) pengguna harus admin/supervisor, dan (3) transaksi belum diposting serta belum memiliki retur.

Pada versi UAT Al-Bahjah 1.34.20, admin/supervisor dapat membuka Riwayat Penjualan > Detail transaksi, lalu menekan tombol **Aktifkan Koreksi Toko**. Tombol ini hanya mengaktifkan toko dari transaksi tersebut, wajib online, dan tetap meminta konfirmasi. Jalur manual juga tersedia di Konfigurasi > Keamanan & Koreksi Transaksi, atau pada profil toko di bagian Keamanan & Koreksi Transaksi Toko.

Mohon dibedakan istilahnya:
- Jika maksudnya **metode pembayaran** (Tunai/Transfer/QRIS/dll.), itu dapat dikoreksi setelah seluruh syarat di atas terpenuhi. Server tetap memeriksa aturan member, batas transaksi, hutang, dan saldo.
- Jika maksudnya **harga barang**, harga satuan transaksi yang sudah selesai memang tidak dapat diketik ulang langsung. Harga lama dipertahankan untuk audit; produk baru memakai harga dari master. Harga penjualan berikutnya diubah melalui master/aturan harga.

Untuk laporan, buka **Laporan > Penjualan > Penjualan Barang Per Pemasok** (atau cari kata “pemasok”). Hasil yang disiapkan untuk UAT sekarang tidak hanya total pemasok, tetapi juga Kode Produk, Produk Terjual, Satuan Terjual, Qty UOM, Qty Dasar, dan Total Penjualan. Hasil dapat diperiksa di layar dan diekspor ke PDF/Excel.

Keterangan **Tanpa Pemasok** berarti produk belum mempunyai histori pengadaan dengan nama pemasok. Untuk saat ini pengelompokan pemasok masih mengikuti pengadaan terakhir produk, belum menelusuri batch/lot historis yang keluar pada setiap penjualan.

Mohon pengujian dilakukan memakai transaksi dummy yang belum posting dan belum retur, bukan transaksi produksi sensitif. Build ini masih untuk UAT lokal; belum kami upload/publish atau nyatakan sudah terpasang di server/toko. Setelah UAT selesai dan ada persetujuan, baru proses rilis/deployment dilanjutkan.

Terima kasih.
