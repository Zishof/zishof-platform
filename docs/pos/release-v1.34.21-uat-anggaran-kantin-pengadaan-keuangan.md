# eBisnis POS v1.34.21 — UAT Anggaran, Kantin, Pengadaan, dan Keuangan

Tanggal paket: 4 September 2026

Target versi aplikasi: 1.34.21 (build 183)

Basis bukti layar: 1.34.20 (build 182), varian eBisnis, server demo `ebisnis.id`

## Ringkasan

Rilis ini menambahkan pemilihan mata anggaran pada Jurnal Umum, memperbaiki isolasi state
antarhalaman posting Akuntansi dan crash tab pada Bayar Pajak, serta menyertakan paket UAT
bergambar untuk Anggaran, Kantin/POS, Pengadaan, dan Keuangan. Paket manual terdiri dari empat
DOCX dan empat PDF dengan 91 halaman, diagram use case, flowchart, langkah operasional, matriks
hasil, pola jurnal, rekonsiliasi, defect/retest, serta lembar sign-off.

## Perubahan aplikasi

- Jurnal Umum dapat memilih mata anggaran tahun transaksi.
- Daftar Jurnal Umum menampilkan kode/nama mata anggaran.
- Mengganti tanggal jurnal ke tahun lain mengosongkan pilihan anggaran untuk mencegah relasi
  lintas tahun.
- Jurnal terposting mengunci pemilih anggaran.
- Perpindahan Posting Penjualan, HPP, dan Kulakan memakai state layar yang terpisah.
- Bayar Pajak memakai ticker yang mendukung dua TabController.
- Integration test baru mencakup seed volume, audit data, posting kategori, dan pengambilan
  screenshot Windows tanpa VNC.

## Hasil UAT volume

### Anggaran

- 500 mata anggaran pada Revisi 1.
- Total pagu Rp44.250.000.000.
- Realisasi Rp574.375.000; sisa Rp43.675.625.000.
- 500 item memiliki penggunaan dataset.
- 50 Jurnal Umum beranggaran berhasil diposting.
- Enam laporan Akuntansi dapat ditampilkan.

### Kantin/POS

- 51 transaksi penjualan dengan total pratinjau Rp26.099.500.
- 107 faktur kulakan; 102 masuk periode pratinjau posting.
- 50 penjualan memenuhi prasyarat akun; satu transaksi tertahan akun pendapatan jenis produk.
- Posting HPP dan Kulakan tetap BLOCKED karena Master Aset produk demo belum mempunyai akun
  persediaan. Sistem sengaja tidak membuat jurnal timpang.

### Pengadaan

- 57 PR, 58 PO termin/non-termin, 55 BAST, 55 tagihan, dan 53 pembayaran vendor.
- Daftar, formulir utama, Proses Transfer, Draft Jurnal, dan Katalog Laporan berhasil dibuka.
- PR/PO diperlakukan sebagai komitmen, bukan jurnal aktual, sesuai praktik akrual umum. Jurnal
  muncul pada pengakuan penerimaan/tagihan dan pembayaran.

### Keuangan

- 156 Uang Muka dan 104 LPJ Uang Muka.
- 105 Kas Besar dan 104 LPJ Kas Besar.
- 104 Kas Kecil dan 104 Penggantian Kas Kecil.
- 51 Reimbursement Pegawai senilai Rp3.675.000; 50 realisasi baru masuk batch transfer.
- Kategori Kas Besar, LPJ Kas Besar, Kas Kecil, dan Penggantian masing-masing memiliki 103
  jurnal terposting pada audit volume.
- 410 jurnal Pengajuan Transfer terposting; Uang Muka dan LPJ masing-masing melampaui 50
  jurnal terposting dari batch sebelumnya dan batch UAT ini.

## Perubahan server yang menyertai UAT

Source server AIS telah diperbarui pada kedua mirror `src/main/java` dan `src/main/src`:

- relasi mata anggaran pada Jurnal Umum menggunakan `workspaceIdTeks`;
- validasi tahun, leaf item, penyimpanan, pembaruan, dan pelepasan penggunaan saat hapus/ubah;
- pencarian mata anggaran sampai 500 hasil;
- dukungan realisasi Jurnal Umum pada utilitas Anggaran;
- pemeliharaan leaf flag setelah perubahan struktur;
- kompilasi Ant memakai UTF-8.

Kompilasi harian ZK5 berhasil. Build ZK9 masih mempunyai 14 inkompatibilitas UI lama yang
tidak disebabkan perubahan ini. WAR tidak dibuat karena deployment dilakukan dengan Ant pada
server.

## Batas dan retest wajib

1. Lengkapi akun Persediaan pada Master/Kelompok Aset produk demo, lalu retest minimal 50
   Posting HPP dan 50 Posting Kulakan.
2. Lengkapi akun Pendapatan pada satu Jenis Produk yang masih tertahan, lalu retest 51/51
   Posting Penjualan.
3. Tautan anggaran pada seluruh rantai PR–PO–BAST–Tagihan–Bayar dan UM–LPJ–Kas perlu dibuktikan
   pada detail dokumen; UAT saat ini membuktikan 500 penggunaan dan 50 Jurnal Umum beranggaran.
4. Tabel RAB masih melaporkan overflow kecil pada mode debug; fungsi dan data tetap bekerja,
   namun layout responsif perlu perbaikan.
5. Closing/tutup periode final tidak dijalankan pada database demo bersama.

## Dokumen

Artefak Word dan PDF berada di `docs/pos/uat-v1.34.21/` dan juga dilampirkan pada GitHub
Release. Dokumen lama tidak ditimpa.

## Build yang diminta

Varian berikut dibangun dari commit dan versi yang sama:

- eBisnis;
- Al-Bahjah;
- Nahl.

Setiap APK dan installer Windows harus melewati verifikasi signature atau diberi label UAT
internal bila host build tidak menyediakan sertifikat produksi. SHA-256 disertakan untuk setiap
artefak rilis.
