# Runbook UAT POS Al-Bahjah 1.34.20

## Status dan tujuan

Dokumen ini menjadi panduan UAT internal untuk dua kebutuhan berikut:

1. koreksi transaksi selesai dari Detail Riwayat Penjualan; dan
2. rincian produk terjual pada laporan **Penjualan Barang Per Pemasok**.

Status terbaru 3 September 2026: perbaikan backend awal sudah masuk SVN r83902; penyempurnaan diagnosis gerbang edit/status posting-retur ikut masuk SVN r83909. Source Flutter koreksi transaksi sudah masuk GitHub pada commit `91f79cf`; build Al-Bahjah 1.34.20 memakai source aplikasi pada commit `6b8b8cc`. Installer Windows dan APK Android dipublikasikan sebagai **prerelease UAT/internal** di [GitHub v1.34.20](https://github.com/Zishof/zishof-platform/releases/tag/v1.34.20).

Publikasi GitHub tersebut hanya mendistribusikan client POS. Backend r83909 **belum otomatis ter-deploy** hanya karena rilis GitHub dibuat. Endpoint aktivasi/validasi koreksi dan struktur tujuh kolom laporan harus di-deploy serta di-restart lewat prosedur server yang berlaku sebelum UAT terpadu dinyatakan siap.

## Makna pesan dan screenshot pengguna

### “Belum bisa mengubah metode harga” pada Detail Riwayat Penjualan

Screenshot tersebut bukan menunjukkan aplikasi rusak. Panel pada screenshot menyatakan kebijakan koreksi transaksi untuk toko itu belum aktif. Tombol edit memang disembunyikan oleh server ketika salah satu gerbang keamanan tidak terpenuhi.

Yang dapat disimpulkan pasti dari screenshot hanya gerbang kebijakannya: **nonaktif**. Versi respons lama memprioritaskan pesan kebijakan, sehingga screenshot itu belum membuktikan akun `ika` sudah atau belum mempunyai hak supervisor. Perbaikan respons server sekarang mengirim status tiap gerbang secara terpisah dan, bila kebijakan serta hak akun sama-sama bermasalah, menjelaskan kedua pekerjaan yang harus diselesaikan.

Istilah “metode harga” perlu dikonfirmasi karena ada dua hal berbeda:

- Jika yang dimaksud **metode pembayaran** (Tunai, Transfer, QRIS, dan sebagainya), nilainya dapat dikoreksi setelah kebijakan dan hak akses terpenuhi, selama transaksi belum posting dan belum memiliki retur. Server tetap memeriksa aturan member, batas transaksi, batas hutang, serta keamanan saldo/deposit.
- Jika yang dimaksud **harga barang**, harga satuan pada transaksi selesai tidak dapat diketik/diubah langsung. Form menampilkannya sebagai informasi. Baris lama mempertahankan harga transaksi yang tersimpan; produk yang ditambahkan memakai harga master saat ini. Harga untuk transaksi berikutnya diubah melalui master/aturan harga. Pembatasan ini menjaga jejak audit dan mencegah perubahan nilai nota tanpa sumber harga yang sah.

Jika maksud pengguna sebenarnya adalah hak mengubah **harga jual/harga beli pada master produk, kulakan, atau grup produk**, itu merupakan kebijakan lain. Admin/supervisor membuka **Konfigurasi > Profil Toko > Kebijakan Ubah Harga**, lalu memilih salah satu:

- aktifkan **Semua pengguna boleh mengubah harga**; atau
- biarkan nonaktif dan centang akun/grup hak akses yang memang boleh mengubah harga.

Sesudah menyimpan Profil Toko, pengguna harus keluar dan masuk kembali agar konfigurasi sesi dimuat ulang. Pesan penolakannya berbeda, yaitu diawali “Anda tidak boleh mengubah harga karena tidak diberikan akses”; pesan tersebut tidak tampak pada screenshot terlampir.

### Permintaan laporan item yang terjual per pemasok

Laporan sebelumnya terlalu agregat sehingga pengguna hanya melihat pemasok dan total. Laporan bersama kini dirinci sampai produk dan satuan yang terjual, sehingga dapat menjawab barang apa yang terjual dari tiap pemasok.

## Akar masalah

1. Hak edit bukan hanya hak menu. Efektivitas koreksi ditentukan bersama oleh kebijakan global/per toko, peran pengguna, dan status transaksi.
2. Respons detail lama hanya menampilkan satu alasan prioritas. Akibatnya kebijakan nonaktif dapat menutupi masalah kedua, yaitu akun belum berhak melakukan koreksi.
3. Status posting/retur sudah ditolak pada saat penyimpanan, tetapi respons detail sebelumnya belum memasukkannya ke keputusan tombol. Pengguna masih mungkin melihat tombol edit lalu baru ditolak saat Simpan.
4. Pesan pada dialog lama menyebut “audit JSON”, padahal implementasi sebenarnya memakai revisi Hibernate Envers dan alasan pada keterangan header.
5. Jalur koreksi lama belum menjalankan kembali semua validasi finansial checkout saat metode/total pembayaran berubah.
6. Query laporan pemasok sebelumnya berhenti pada agregat pemasok dan belum memperlihatkan identitas produk/UOM yang terjual.

## Perbaikan yang tersedia untuk UAT

### Koreksi transaksi

- Detail transaksi mengembalikan status kebijakan global, kebijakan toko, hak aktivasi, toko transaksi, dan keputusan apakah transaksi boleh diedit.
- Detail juga mengembalikan `penggunaBolehEditTransaksi`, `punyaHeaderTransaksi`, `transaksiSudahPosting`, dan `transaksiMemilikiRetur`, sehingga dukungan teknis dapat membedakan penyebab tanpa menebak.
- Keputusan tombol edit dan aktivasi cepat sekarang langsung memasukkan status posting/retur. Transaksi terkunci tidak lagi menawarkan aksi yang pasti gagal ketika disimpan.
- Bila kebijakan dan hak akun sama-sama belum terpenuhi, pesan menuliskan kedua blocker dan urutan perbaikannya.
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

### Langkah pemberian akses akun yang diminta pada WA

Untuk akun toko tertentu (misalnya akun pada screenshot), jangan mengubah database secara manual dan jangan membagikan sandi admin:

1. Admin/supervisor masuk ke POS dengan toko yang benar.
2. Buka **Konfigurasi > Akun Pengguna**.
3. Cari akun yang dimaksud dan buka ubah akun.
4. Aktifkan sakelar **Supervisor**, lalu simpan.
5. Bila organisasi memakai hak berbasis grup, alternatifnya atur grup akun sebagai grup berizin **Supervisor** pada pengelolaan Hak Akses.
6. Pengguna keluar lalu masuk kembali; tekan **Sinkronkan** dan **Muat Ulang**.
7. Admin mengaktifkan kebijakan koreksi global/per toko, atau akun supervisor menekan **Aktifkan Koreksi Toko** dari Detail transaksi.
8. Uji menggunakan transaksi dummy yang belum posting dan belum retur.

Hak Supervisor jauh lebih luas daripada sekadar mengubah metode pembayaran. Berikan hanya kepada akun yang memang berwenang. Jika kebutuhan sebenarnya hanya mengubah harga master, gunakan daftar akun/grup pada **Kebijakan Ubah Harga** dan jangan menaikkan akun menjadi Supervisor tanpa kebutuhan operasional.

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

Screenshot laporan masih menampilkan tiga kolom lama (`Pemasok`, `Qty Terjual`, `Total Penjualan`) dan judul lama. Itu merupakan bukti lingkungan yang dipakai pengirim WA belum menjalankan query backend baru. Menyalin installer Desktop saja tidak akan menambah kolom, karena definisi kolom dan baris laporan berasal dari endpoint server. Backend harus diperbarui/restart terlebih dahulu; setelah itu klik **Sinkronkan/Muat Ulang** dan jalankan ulang laporan supaya cache hasil lama tidak disangka sebagai hasil terbaru.

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

### Bila yang dimaksud benar-benar hak mengubah harga master

1. Masuk sebagai admin/supervisor dan pilih toko yang benar.
2. Buka **Konfigurasi > Profil Toko > Kebijakan Ubah Harga**.
3. Untuk akses terbatas, biarkan **Semua pengguna boleh mengubah harga** nonaktif.
4. Tekan **Muat ulang** pada daftar akun/grup, kemudian centang akun atau grup yang berhak.
5. Tekan **Simpan Profil Toko**.
6. Pengguna keluar lalu masuk kembali dan melakukan Sinkronkan/Muat Ulang.
7. Uji perubahan harga pada master Produk/Kulakan/Grup Produk, bukan pada nota final yang sudah selesai.

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
- Pesan detail membedakan kebijakan nonaktif, hak akun tidak cukup, transaksi sudah posting, transaksi sudah retur, dan header transaksi legacy yang tidak dapat dikoreksi.
- Aktivasi cepat hanya mengubah toko transaksi dan gagal secara jelas saat offline.
- Semua koreksi finansial berisiko ditolak oleh server, bukan hanya UI.
- Koreksi yang valid mengubah total/stok secara atomik dan meninggalkan audit yang dapat ditelusuri.
- Laporan layar, PDF, Excel, dan ZK memperlihatkan produk/UOM dengan angka yang konsisten.
- Tidak ada data produksi sensitif yang dipakai selama UAT.

## Validasi teknis lokal

- Targeted Flutter tests koreksi + laporan pemasok + posting akun: **12/12 lulus**.
- Suite Flutter penuh setelah sinkronisasi kontrak source backend: **750/750 lulus**. Satu kegagalan awal pada `riwayat_revisi_hak_test.dart` diisolasi sebagai parser test lama yang menganggap kode entitas `si_customer` sebagai kunci menu; parser diperbaiki agar memeriksa nilai pemetaan sebenarnya (`master_customer`). Test terkait lulus **4/4**, lalu suite penuh lulus.
- Flutter analyze proyek dengan `--no-pub --no-fatal-infos`: **exit 0**; tersisa 50 lint level `info` lama, tanpa warning/error penghambat.
- Kompilasi terarah Java 8 setelah penyempurnaan gerbang: **lulus**, menghasilkan 5.176 class (termasuk dependensi source yang perlu dikompilasi ulang).
- `KantinKoreksiTransaksiSelfTest`: **lulus semua 17 aturan**, termasuk hak akun, kebijakan, header legacy, posting, retur, dan hak aktivasi cepat.
- `LaporanKantinSqlSelfTest`: **lulus semua 18 aturan**.
- Percobaan memakai `ant/build.xml` lama tidak dipakai sebagai bukti kelulusan: skrip itu masih menunjuk `web/WEB-INF/lib`, sedangkan library proyek saat ini berada di `src/main/webapp/WEB-INF/lib`, sehingga berhenti sebelum kompilasi. Tidak ada deploy yang dijalankan.
- Build khusus varian Al-Bahjah menghasilkan **2/2 artefak**. Build Windows pertama terhenti karena executable hasil build lama masih berjalan dan mengunci `ebisnis.exe`; setelah PID serta path diverifikasi dan proses itu ditutup, build ulang Windows-only berhasil. APK yang sudah valid tidak dibangun ulang.
- Installer Windows lokal: `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\release-artifacts\semua-varian\1.34.20\Al-Bahjah-POS-Setup-1.34.20.exe` (85.955.122 byte; SHA-256 `3F176FF6960C70BEE079ADBF437E06D72DED6FE47FCE1DC7B435E986E9416C5A`). Metadata: ProductName **Al-Bahjah POS**, ProductVersion **1.34.20**. Signature: **unsigned/UAT**.
- APK Android lokal: `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\release-artifacts\semua-varian\1.34.20\app-albahjah-release.apk` (190.177.824 byte; SHA-256 `FFC5ADD5DD31B416ACCDB440EF11D6F293F4B9F097FB4B567775C74F953BBDC2`). Metadata: package `id.zishof.ebisnis.albahjah`, label **Al-Bahjah POS**, versionName **1.34.20**, versionCode **182**. Signature: sertifikat **Android Debug/UAT**.
- Smoke-run executable Windows: **lulus**; proses hidup dan responsif selama pemeriksaan, kemudian dihentikan kembali secara terkendali.

### Status signing dan batas distribusi

- Kedua artefak ini untuk UAT/internal, bukan paket produksi final.
- APK debug-signed mungkin tidak dapat meng-upgrade instalasi produksi yang memakai sertifikat lain. Jangan uninstall aplikasi operasional hanya untuk memaksakan APK UAT karena data lokal dapat ikut terhapus.
- Installer Windows unsigned dapat memunculkan peringatan SmartScreen. Distribusi produksi memerlukan build ulang dengan sertifikat Authenticode organisasi.
- Sebelum instalasi, selesaikan sinkronisasi dan backup data lokal. Gunakan perangkat uji, bukan terminal kasir produksi, sampai UAT dan signing produksi selesai.

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

Screenshot itu baru memastikan syarat nomor 1 belum aktif. Pada respons lama, pesan kebijakan tampil lebih dulu sehingga dari screenshot saja belum bisa dipastikan apakah akun **ika** juga sudah mempunyai hak supervisor. Mohon admin memeriksa keduanya: aktifkan kebijakan koreksi, lalu cek **Konfigurasi > Akun Pengguna > pilih akun > Supervisor**. Sesudah disimpan, pengguna perlu keluar/masuk kembali, tekan Sinkronkan dan Muat Ulang, lalu buka ulang Detail transaksi. Karena hak Supervisor cukup luas, berikan hanya kepada akun yang memang berwenang.

Pada versi UAT Al-Bahjah 1.34.20, admin/supervisor dapat membuka Riwayat Penjualan > Detail transaksi, lalu menekan tombol **Aktifkan Koreksi Toko**. Tombol ini hanya mengaktifkan toko dari transaksi tersebut, wajib online, dan tetap meminta konfirmasi. Jalur manual juga tersedia di Konfigurasi > Keamanan & Koreksi Transaksi, atau pada profil toko di bagian Keamanan & Koreksi Transaksi Toko.

Mohon dibedakan istilahnya:
- Jika maksudnya **metode pembayaran** (Tunai/Transfer/QRIS/dll.), itu dapat dikoreksi setelah seluruh syarat di atas terpenuhi. Server tetap memeriksa aturan member, batas transaksi, hutang, dan saldo.
- Jika maksudnya **harga barang**, harga satuan transaksi yang sudah selesai memang tidak dapat diketik ulang langsung. Harga lama dipertahankan untuk audit; produk baru memakai harga dari master. Harga penjualan berikutnya diubah melalui master/aturan harga.
- Jika maksudnya hak mengubah **harga jual/harga beli pada master Produk/Kulakan/Grup Produk**, buka **Konfigurasi > Profil Toko > Kebijakan Ubah Harga**. Admin dapat mengizinkan semua pengguna atau hanya mencentang akun/grup tertentu, kemudian Simpan Profil Toko dan minta pengguna login ulang. Ini kebijakan berbeda dari koreksi transaksi pada screenshot.

Untuk laporan, buka **Laporan > Penjualan > Penjualan Barang Per Pemasok** (atau cari kata “pemasok”). Hasil yang disiapkan untuk UAT sekarang tidak hanya total pemasok, tetapi juga Kode Produk, Produk Terjual, Satuan Terjual, Qty UOM, Qty Dasar, dan Total Penjualan. Hasil dapat diperiksa di layar dan diekspor ke PDF/Excel.

Screenshot yang dikirim masih menunjukkan tiga kolom versi lama. Karena struktur laporan dikirim oleh server, kolom rincian baru baru akan muncul setelah backend versi UAT diperbarui/restart; update aplikasi Desktop saja tidak cukup. Setelah backend aktif, tekan Sinkronkan/Muat Ulang lalu jalankan ulang laporan untuk periode yang sama.

Keterangan **Tanpa Pemasok** berarti produk belum mempunyai histori pengadaan dengan nama pemasok. Untuk saat ini pengelompokan pemasok masih mengikuti pengadaan terakhir produk, belum menelusuri batch/lot historis yang keluar pada setiap penjualan.

Build Al-Bahjah POS 1.34.20 untuk UAT/internal sudah dipublikasikan di:
https://github.com/Zishof/zishof-platform/releases/tag/v1.34.20

Pilihan unduhan:
- Windows: `Al-Bahjah-POS-Setup-1.34.20.exe`
- Android: `app-albahjah-release.apk`
- File `.sha256.txt` tersedia untuk memeriksa keutuhan masing-masing unduhan.

Catatan penting: APK masih memakai sertifikat Android Debug/UAT dan installer Windows belum mempunyai tanda tangan Authenticode. Jadi gunakan perangkat UAT, jangan uninstall aplikasi produksi untuk memaksakan pemasangan APK, dan lakukan backup serta sinkronisasi sebelum instalasi. Untuk Windows, SmartScreen mungkin menampilkan peringatan karena installer belum ditandatangani.

Urutan UAT yang disarankan:
1. Selesaikan Sinkronkan pada aplikasi lama dan backup data lokal.
2. Tutup POS, instal versi 1.34.20 pada perangkat uji, lalu login ke toko yang benar.
3. Tekan Sinkronkan dan Muat Ulang.
4. Admin cek hak akun dan mengaktifkan kebijakan koreksi toko.
5. Uji koreksi memakai transaksi dummy yang belum posting dan belum retur.
6. Setelah backend r83909 di-deploy/restart, jalankan laporan Penjualan Barang Per Pemasok dan cocokkan tujuh kolomnya dengan nota serta ekspor PDF/Excel.

Perlu ditegaskan bahwa publikasi installer/APK tidak sekaligus meng-update server. Source backend sudah masuk SVN, tetapi tim server tetap perlu men-deploy r83909 dan me-restart aplikasi server. Sebelum langkah backend itu selesai, tombol/validasi baru dapat belum lengkap dan laporan masih dapat menampilkan tiga kolom lama seperti pada screenshot.

Terima kasih.
