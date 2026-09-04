# eBisnis POS v1.34.22 — UAT E2E Kantin dan Transparansi Akun Posting

Tanggal paket: 4 September 2026

Versi aplikasi: 1.34.22 (build 184)

Varian rilis: eBisnis, Al-Bahjah, dan Nahl

Lingkungan UAT: varian eBisnis, server demo `ebisnis.id`

## Ringkasan

Rilis ini menutup temuan UAT Kantin yang sebelumnya tertahan karena akun Pendapatan,
Persediaan, HPP, Kas, Piutang, atau Utang belum lengkap. Pemetaan akun telah dirapikan memakai
akun daun yang relevan dari daftar akun pengguna, data contoh telah dinaikkan melewati batas
minimum 100 record, seluruh batch berhasil diposting, dan enam laporan Akuntansi ditelusuri
sampai halaman terakhir atau bagian terbawah.

Perubahan aplikasi yang paling terlihat adalah panel **Dari mana akun jurnal diambil?** pada
setiap menu posting dalam cakupan Kantin/Akuntansi: Posting Penjualan, Posting HPP, Posting
Kulakan, Posting Bayar Hutang, Posting Terima Piutang, dan Posting Penyesuaian. Panel selalu
menjelaskan sumber sisi Debet, sumber sisi Kredit, urutan fallback pemetaan, syarat akun daun,
dan syarat total Debet sama dengan Kredit. Tombol **Sesuaikan Akun Debet** dan **Sesuaikan
Akun Kredit** tersedia di bagian atas serta pada baris yang belum siap. Tombol membuka master
sumber yang tepat, lalu pratinjau dimuat ulang setelah pengguna kembali.

Manual Word dan PDF yang baru tidak menimpa dokumen v1.34.21. Dokumen baru berjumlah 86
halaman A4 landscape dan memuat 27 tangkapan layar penuh, 81 diagram, serta penjelasan
operasional terperinci untuk setiap tangkapan layar. Isinya menggabungkan manual pengguna, skenario UAT,
use case, flowchart, aliran data/ERD ringkas, bukti hasil, prosedur koreksi, dan lembar sign-off.

Seluruh 27 halaman penjelasan kini ditulis khusus berdasarkan bukti pada layar masing-masing.
Panjang uraian mengikuti kebutuhan proses; teks umum yang sebelumnya berulang telah dihapus.
Setiap bagian membahas konteks, cara membaca, tindakan pengguna, makna akuntansi, dan hasil UAT
yang relevan dengan menu, angka, akun, status, atau laporan yang sedang ditampilkan.

Revisi penyajian terakhir merapikan seluruh diagram use case. Hubungan dari aktor sekarang
memakai satu jalur cabang di area kosong dan kepala panah berhenti sebelum batas node. Tidak ada
lagi garis yang melintasi kotak proses atau teks seperti pada susunan horizontal sebelumnya.

Revisi UAT lanjutan menambahkan batch nyata `UAT-E2E-POS-20260904-R2` dan
`UAT-E2E-KUL-20260904-R2`, masing-masing 100 dokumen. Tiga screenshot panel akun yang semula
memperlihatkan keadaan kosong diganti dengan bukti pratinjau berisi data, akun Debet/Kredit,
nilai, status siap, dan tombol koreksi. Seluruh laporan juga diambil ulang memakai renderer kolom
fleksibel yang memenuhi lebar layar sampai sisi kanan; kolom uraian menjadi lebih mudah dibaca
dan angka yang dapat ditelusuri tetap rata kanan serta dapat diklik pada seluruh area selnya.

## Perubahan aplikasi

### 1. Asal akun Debet dan Kredit terlihat di layar

Panel keterangan baru menerangkan pemetaan berikut.

| Proses | Debet | Sumber Debet | Kredit | Sumber Kredit |
|---|---|---|---|---|
| Penjualan tunai | Kas/Bank | Cara Pembayaran atau Toko | Pendapatan dan PPN bila ada | Jenis Produk |
| Penjualan kredit | Piutang Usaha | Toko | Pendapatan dan PPN bila ada | Jenis Produk |
| HPP | Beban Pokok Penjualan | Jenis Produk atau Kelompok Aset | Persediaan | Master Aset atau Kelompok Aset |
| Kulakan tunai | Persediaan/Pembelian | Master Aset atau Kelompok Aset | Kas/Bank | Cara Pembayaran atau Toko |
| Kulakan kredit | Persediaan/Pembelian | Master Aset atau Kelompok Aset | Utang Usaha | Supplier/Penyedia |
| Bayar Utang | Utang Usaha | Supplier/Penyedia | Kas/Bank | Cara Pembayaran atau Toko |
| Terima Piutang | Kas/Bank | Cara Pembayaran atau Toko | Piutang Usaha | Toko |
| Penyesuaian | Sesuai arah mutasi | Jenis Produk, Master/Kelompok Aset, atau Toko | Akun lawan sesuai arah mutasi | Master sumber yang relevan |

Sistem tetap menghitung draf jurnal dari dokumen bisnis. Pengguna tidak mengubah baris jurnal
hasil kalkulasi secara langsung karena cara itu hanya memperbaiki satu draf dan berisiko
menghilangkan jejak asal. Koreksi dilakukan pada master sumber agar transaksi sejenis berikutnya
memakai pemetaan yang sama.

### 2. Tombol koreksi akun langsung

- Tombol global Debet dan Kredit selalu tersedia di layar posting.
- Baris yang tidak siap menampilkan tombol koreksi pada baris itu sendiri.
- Alasan dari server dipakai untuk menyaring master tujuan sehingga pengguna tidak menebak.
- Penjualan mengarahkan sisi Debet ke Cara Pembayaran dan sisi Kredit ke Jenis Produk.
- HPP mengarahkan sisi Debet ke Jenis Produk/Kelompok Aset dan sisi Kredit ke Master/Kelompok Aset.
- Kulakan mengarahkan sisi Debet ke Master/Kelompok Aset serta sisi Kredit ke Supplier, Toko,
  atau Cara Pembayaran sesuai metode transaksi.
- Sesudah master disimpan dan pengguna kembali, aplikasi otomatis memuat ulang pratinjau.
- Posting tetap dinonaktifkan bila akun kosong, akun induk, nilai nol, atau total Debet dan Kredit
  belum seimbang.

### 3. Jendela Windows dimaksimalkan saat aplikasi dibuka

Runner Windows sekarang membuka jendela utama dengan status maximized. Perubahan ini membuat
area kerja langsung memakai lebar dan tinggi layar yang tersedia, mengurangi kebutuhan resize
manual, dan menghasilkan tangkapan layar UAT yang lebih luas. Mode ini tetap menggunakan work
area Windows sehingga taskbar dan kontrol sistem tidak tertutup seperti exclusive fullscreen.

### 4. Ketahanan pengambilan data pemetaan

Timeout panggilan pemetaan akun diperpanjang menjadi lima menit untuk operasi audit/perbaikan
volume yang memang dapat memeriksa banyak master. Perubahan ini tidak melonggarkan validasi
bisnis dan tidak membuat posting dipaksakan ketika server mengembalikan alasan belum siap.

### 5. Perangkat UAT yang dapat diulang

Integration test baru atau diperbarui mencakup:

- seed Penjualan dan Kulakan dengan prefix idempoten;
- perbaikan pemetaan akun Kantin berdasarkan akun daun yang dipilih;
- unpost terkontrol untuk membuktikan pratinjau sebelum posting;
- audit jumlah record dan transaksi tertahan;
- posting Penjualan, HPP, dan Kulakan;
- audit keseimbangan seluruh jurnal;
- perbaikan dan repost LPJ Kas Besar pada data historis;
- smoke test Akuntansi, Jurnal Umum, dan enam laporan;
- ukuran permukaan Windows 2560 × 1392 untuk bukti layar penuh.

### 6. Tata letak penuh untuk seluruh laporan

Renderer generik laporan tidak lagi memberi lebar tetap 150 piksel pada setiap kolom. Semua
laporan katalog—termasuk Laba Rugi, Neraca, Arus Kas, Keseluruhan Jurnal, Buku Besar, dan Neraca
Saldo—sekarang membagi ruang secara proporsional: uraian/nama mendapat porsi terbesar dan angka
mendapat porsi yang stabil di sisi kanan. Perubahan dilakukan pada satu renderer bersama sehingga
berlaku pula pada laporan lain tanpa kode khusus per judul. Sel angka yang bergaris bawah juga
memenuhi seluruh lebar kolom sehingga target klik untuk membuka data penyusun lebih jelas.

## Akun contoh yang diverifikasi

| Peran akun | Kode dan nama |
|---|---|
| Kas | 111.101 — KAS YAYASAN |
| Piutang toko | 131.300 — PIUTANG USAHA TOKO |
| Persediaan | 151.200 — PERSEDIAAN BARANG LAINNYA |
| Utang toko/vendor | 310.600 — UTANG USAHA TOKO |
| Pendapatan Kantin | 410.900 — PENDAPATAN PENJUALAN TOKO |
| HPP Kantin | 510.900 — BEBAN POKOK PENJUALAN TOKO |

Keenam akun telah diperiksa sebagai akun daun yang dapat menerima posting. Relasi penting yang
dipertahankan adalah akun Persediaan pada kredit HPP harus sama dengan akun Persediaan pada
debet Kulakan. Dengan relasi itu, pembelian menaikkan persediaan dan penjualan mengurangi
persediaan melalui HPP tanpa memutus jejak Buku Besar.

## Hasil UAT end-to-end

Periode bukti: 1–30 September 2026.

| Pemeriksaan | Target | Aktual | Status |
|---|---:|---:|---|
| Data Penjualan | 100–10.000 | 202 transaksi kumulatif | LULUS |
| Data Kulakan | 100–10.000 | 307 faktur kumulatif | LULUS |
| Batch Penjualan R2 | minimal 100 | 100 transaksi; Rp49.849.500 | LULUS |
| Batch Kulakan R2 | minimal 100 | 100 faktur; Rp112.500.000 | LULUS |
| Posting Penjualan R2 | tertahan 0 | 100/100; Rp49.849.500 | LULUS |
| Posting HPP R2 | tertahan 0 | 100 transaksi → 1 agregat; 199 unit; Rp39.800.000 | LULUS |
| Posting Kulakan | tertahan 0 | 100/100; Rp112.500.000 | LULUS |
| Produk tanpa Master Aset | 0 | 0 | LULUS |
| Produk tanpa akun Persediaan | 0 | 0 | LULUS |
| Jenis Produk tanpa Pendapatan | 0 | 0 | LULUS |
| Jenis Produk tanpa HPP | 0 | 0 | LULUS |
| Penyedia tanpa akun Utang | 0 | 0 | LULUS |
| Keseimbangan jurnal | selisih Rp0 | Debet=Kredit Rp1.044.827.514 | LULUS |
| Jurnal tidak seimbang | 0 | 0 dari 3.303 baris | LULUS |
| Laporan | 6/6 | 6/6 sampai akhir/terbawah | LULUS |

Urutan UAT yang dibuktikan adalah transaksi Penjualan POS → histori Penjualan → histori
Kulakan → periksa master Akuntansi → pratinjau Penjualan → pratinjau HPP → pratinjau Kulakan
→ periksa draf → posting → audit Keseluruhan Jurnal → Laba Rugi → Neraca → Arus Kas → Buku
Besar → Neraca Saldo. Laporan panjang disimpan dua kali: halaman awal dan halaman terakhir atau
posisi scroll terbawah.

## Jurnal Umum

Manual baru menambahkan langkah lengkap pembuatan, pemeriksaan, penyimpanan draf, persetujuan,
posting, pembatalan posting pada periode terbuka, jurnal pembalik, dan jurnal koreksi. Contoh
visual memakai jurnal seimbang Rp750.000: Debet 512.115 Beban Administrasi Umum Lainnya dan
Kredit 111.101 Kas Yayasan. Form menampilkan indikator **Siap disimpan** hanya ketika nominal
positif dan total kedua sisi sama.

Jenis jurnal yang dijelaskan meliputi Penjualan Kantin, HPP Kantin, Kulakan, Bayar Utang,
Terima Piutang, Kas Masuk, Kas Keluar, Uang Muka, LPJ, Saldo Awal, Penyesuaian, Penyusutan,
Pembalik, Koreksi, dan Tutup Buku. Manual juga menekankan bahwa kejadian yang mempunyai menu
otomatis harus diposting melalui menu tersebut; Jurnal Umum manual tidak boleh dipakai untuk
menduplikasi Penjualan, HPP, atau Kulakan.

## Temuan historis dan retest

Audit awal menemukan selisih Rp2.400.000 pada jurnal LPJ Kas Besar nomor
`20260924700022994`. Jurnal mempunyai Debet Bank Rp100.000 dan Kredit Uang Muka Rp2.500.000,
tetapi kehilangan Debet beban Rp2.400.000. Logika server telah dikoreksi agar akun beban rincian
selalu dipopulasi. Sebanyak 103 LPJ Kas Besar kemudian dibatalkan postingnya secara terkontrol
dan diposting ulang. Audit pascaretest menemukan nol jurnal tidak seimbang dan total seluruh
baris pada tahap tersebut kembali Debet=Kredit Rp842.678.014. Setelah batch R2 Penjualan, HPP,
dan Kulakan diposting, audit akhir meningkat menjadi 3.303 baris dengan total Debet dan Kredit
masing-masing Rp1.044.827.514 serta selisih tetap Rp0.

## Verifikasi server

- Helper pemetaan akun pada kedua mirror source server telah dioptimalkan.
- Logika LPJ Kas Besar telah mengisi kembali baris beban rincian.
- Kompilasi penuh Ant berhasil untuk 7.525 source Java.
- WAR tidak dibuat, sesuai prosedur deployment pengguna yang menjalankan Ant langsung di server.
- Aplikasi klien tidak mem-bypass validasi server; server tetap menjadi otoritas akhir posting.

## Dokumen rilis

Folder `docs/pos/uat-v1.34.22/` berisi:

- `Manual-UAT-E2E-Kantin-POS-Kulakan-Akuntansi-100-Record-Jurnal-Umum-v1.34.22-20260904.docx`;
- `Manual-UAT-E2E-Kantin-POS-Kulakan-Akuntansi-100-Record-Jurnal-Umum-v1.34.22-20260904.pdf`;
- `uat-kantin-akun-lengkap-evidence.json`.

Manual PDF telah dirender ke 86 gambar halaman dan diperiksa melalui contact sheet serta sampel
resolusi penuh. Tidak ditemukan halaman limpahan kosong, screenshot terpotong, tabel keluar
margin, diagram terpisah, atau laporan yang berhenti sebelum bagian terakhir.

## Build dan distribusi

Build dilakukan dari commit rilis yang sama untuk tiga varian berikut:

| Varian | Windows | Android |
|---|---|---|
| eBisnis | `eBisnis-Setup-1.34.22.exe` | `app-ebisnis-release.apk` |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.22.exe` | `app-albahjah-release.apk` |
| Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.22.exe` | `app-nahl-release.apk` |

SHA-256 diterbitkan sebagai berkas pendamping untuk setiap installer dan APK. Jika host build
tidak memiliki sertifikat produksi, artefak ditandai sebagai UAT/internal: APK memakai
sertifikat debug yang terverifikasi dan installer Windows tidak mempunyai Authenticode.

Snapshot build: commit `c05c2d18dcc3c2d78d3585d4a01ba74e388d3f00`. Keenam artefak dibangun
secara serial dari worktree bersih agar folder output bersama tidak saling menimpa.

| Artefak | Ukuran (byte) | SHA-256 |
|---|---:|---|
| `eBisnis-Setup-1.34.22.exe` | 50.035.063 | `ff00fe6c4bbcda77bf94e27141b295e39c67f7204f6b70fa09d56b6a4cb06bca` |
| `app-ebisnis-release.apk` | 154.000.962 | `4dc937460e7cfddb5695a14a82858e3502a221b7df668878e4b6aca0f261743b` |
| `Al-Bahjah-POS-Setup-1.34.22.exe` | 50.095.681 | `703ab998d64168fee2455348d77bd243cf3d885b29b2c37b39b68c5ad96410c2` |
| `app-albahjah-release.apk` | 154.061.997 | `bd89882139720b24cbcf09d6d5e1eb35dbff2c4d4275b9f52cd0b8e26fa6881b` |
| `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.22.exe` | 50.249.299 | `d10082ca65565c113fe07ec7d59d135442aaf0a81a5d182c5f10868a04c19d34` |
| `app-nahl-release.apk` | 154.083.403 | `54f73c5befeb400f09ebeb5aaa983b674e2f60447a5d19ed00d110249faacd02` |

Metadata APK diverifikasi memakai Android Build Tools 36.0.0:

- eBisnis: package `id.zishof.ebisnis`, versionName `1.34.22`, versionCode `184`;
- Al-Bahjah: package `id.zishof.ebisnis.albahjah`, versionName `1.34.22`, versionCode `184`;
- Nahl: package `id.zishof.ebisnis.nahl`, versionName `1.34.22`, versionCode `184`.

ProductVersion ketiga installer Windows juga terbaca `1.34.22`. Isi berkas checksum dihitung
ulang setelah penyalinan dan seluruhnya cocok dengan artefak. Status distribusi rilis ini adalah
**UAT/internal**: ketiga APK Debug/UAT signed dan ketiga installer Windows unsigned.

## Verifikasi kualitas aplikasi

- Seluruh suite unit/widget test lulus: **763 test**.
- Test khusus sumber dan tombol koreksi akun lulus: **7/7**.
- Analisis statis menemukan **0 error** dan **0 warning** pada perubahan rilis.
- Terdapat 45 lint tingkat `info` yang sudah tersebar pada source lama dan tidak memblokir build.
- Build Android dan Windows sukses untuk ketiga varian.
- Kompilator Windows mencatat warning konversi numerik dari dependency `flutter_zxing`; tidak ada
  error CMake/linker dan warning tersebut tidak berasal dari perubahan rilis ini.

## Prosedur operator ketika akun salah atau jurnal belum balance

1. Jangan menekan posting berulang kali dan jangan membuat Jurnal Umum pengganti.
2. Baca alasan pada baris yang berwarna peringatan.
3. Tentukan sisi yang bermasalah: Debet, Kredit, atau keduanya.
4. Klik **Sesuaikan Akun Debet** atau **Sesuaikan Akun Kredit** pada baris tersebut.
5. Pilih master yang ditawarkan bila terdapat lebih dari satu sumber.
6. Cari akun berdasarkan kode/nama, pilih akun daun yang substansinya benar, lalu simpan.
7. Kembali ke layar posting; tunggu pratinjau dimuat ulang.
8. Pastikan status menjadi **Siap diposting** dan pasangan akun tampil lengkap.
9. Pastikan grand total Debet sama dengan Kredit.
10. Posting, kemudian telusuri nomor referensi pada Keseluruhan Jurnal dan Buku Besar.

## Catatan kompatibilitas dan rollback

- Perubahan panel dan tombol bersifat aditif; format API posting yang sudah ada tetap dipakai.
- Default maximize hanya berlaku pada runner Windows dan tidak mengubah layout Android.
- Bila ditemukan regresi UI, pengguna dapat kembali ke v1.34.21 tanpa migrasi basis data klien.
- Bila ditemukan perbedaan jurnal, hentikan posting batch berikutnya, simpan bukti referensi,
  dan lakukan rekonsiliasi sebelum rollback aplikasi atau server.
- Database demo merupakan lingkungan bersama; closing/tutup buku final tidak dijalankan agar
  periode tetap dapat dipakai untuk retest.
