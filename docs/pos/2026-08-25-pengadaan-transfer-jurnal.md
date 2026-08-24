# Pengadaan dan proses transfer — 25 Agustus 2026

## Ruang lingkup

Perubahan ini menindaklanjuti lima koreksi UI dan alur akuntansi:

1. Tombol `Dari PR` dan `Buat PO` dipindahkan ke header halaman Pemesanan Pembelian (PO), sehingga tidak lagi menutup dashboard/tabel.
2. Tombol `Tanya Jawab` dan `Bantuan` pada header PO dan Terima Tagihan Vendor disembunyikan karena bantuan mengambang (`?`) tetap tersedia.
3. Input tanggal pada dialog Proses Transfer disamakan dengan kontrol filter lain melalui `InputDecorator`, termasuk label, ikon kalender, border, dan tinggi yang proporsional.
4. Aksi `Realisasikan (dana cair)` dinonaktifkan setelah status sudah terealisasi. Pemeriksaan dibuat toleran terhadap variasi teks status dan juga memeriksa `realisasikanOleh`.
5. Realisasi pembayaran vendor langsung membuat jurnal umum melalui posting satu Proses Transfer, tanpa mengharuskan pengguna berpindah ke halaman Draft Jurnal/Posting.

## File yang berubah

### Flutter Desktop/Android

- `apps/ebisnis/lib/widgets/app_shell.dart`
- `apps/ebisnis/lib/screens/pengadaan_po_screen.dart`
- `apps/ebisnis/lib/screens/pengadaan_tagihan_screen.dart`
- `apps/ebisnis/lib/screens/proses_transfer_screen.dart`

### Backend Java

- `C:/opt/AIS/ais/src/main/src/ais/action/servlet/api/ProsesTransferApiHelper.java`
- `C:/opt/AIS/ais/src/main/src/ais/action/master/akunting/PostingProsesTransferAction.java`
- Salinan sinkron pada `C:/opt/AIS/ais/src/main/java/ais/...`

## Catatan integritas akuntansi

- Realisasi disimpan lebih dahulu, lalu proses transfer yang sama diposting ke jurnal melalui `PostingProsesTransferAction.postingSatu(...)`.
- Pemanggilan ulang bersifat idempoten: riwayat posting yang sudah ada tidak dibuat ulang.
- Pembatalan realisasi ditolak apabila jurnal telah terbentuk. Pengguna harus membatalkan posting jurnal terlebih dahulu agar status pencairan dan buku besar tidak berbeda.
- Sesi Hibernate eksplisit ditutup pada blok `finally` melalui `HibernateUtil.closeSessionQuietly(...)`; `currentSession()` tidak ditutup manual.
- Kode tetap kompatibel dengan Java 1.7/gaya Java 1.6.

## Verifikasi yang telah dijalankan

- `dart analyze` terarah pada empat file Flutter: **lulus, No issues found**.
- `javac -source 7 -target 7` untuk `ProsesTransferApiHelper.java` dan `PostingProsesTransferAction.java`: **lulus**. Hanya peringatan bootstrap/deprecated/unchecked dari toolchain lama.
- `git diff --check`: tidak ada whitespace error; hanya peringatan normalisasi LF/CRLF Windows.
- Dua salinan `ProsesTransferApiHelper.java` (`src/main/src` dan `src/main/java`) memiliki hash SHA-256 identik.

## UAT runtime yang disarankan sebelum rilis

1. Buka PO dan pastikan `Dari PR`, `Buat PO`, serta muat ulang tampil di header dan tidak menutup isi.
2. Buka Terima Tagihan Vendor dan pastikan hanya bantuan mengambang yang tersedia.
3. Buat Proses Transfer baru dan periksa tampilan/pemilihan tanggal.
4. Setujui lalu realisasikan satu pembayaran vendor; pastikan status menjadi `Terealisasi`, aksi realisasi nonaktif, dan API mengembalikan `jurnalOtomatis=true` serta `jumlahJurnal`.
5. Periksa Jurnal Umum: debit/kredit harus terbentuk dari DPC terkait dan seimbang.
6. Ulangi permintaan realisasi yang sama; pastikan tidak timbul jurnal ganda.
7. Coba batalkan realisasi setelah jurnal terbentuk; proses harus ditolak dengan pesan agar posting jurnal dibatalkan lebih dahulu.

## Rilis Desktop

- Versi: `1.33.82+140`.
- Varian: Al-Bahjah POS dan eBisnis POS (Windows installer).
- Build memakai `apps/ebisnis/tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah,ebisnis`.
- Backend terkait sudah tersimpan pada SVN sampai revisi `r78258`.
