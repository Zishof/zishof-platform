# POS Apotik v1.34.22 (build 184)

Tanggal rilis: 4 September 2026

Rilis ini menggabungkan layar farmasi untuk pasien/keluarga, UAT volume layanan obat dan procure-to-pay, pemetaan akun dari workbook pengguna, serta manual operasional dan laporan UAT yang telah dirender dan diperiksa secara visual. Keputusan UAT adalah **LULUS BERSYARAT**: fungsi klien dan transaksi yang tercantum sebagai PASS dapat dipakai untuk pilot terkontrol, sedangkan integrasi antrean live, provision katalog volume, jurnal otomatis, kulakan generik, validasi angka laporan, dan signing produksi harus menuntaskan prasyarat di bagian “Batasan dan tindak lanjut”.

## Perubahan utama

- Menambahkan layar antrean farmasi publik yang menampilkan obat jadi dan obat racikan secara berdampingan, identitas pasien tersamar, status proses, loket, jam, dan panel edukasi.
- Menambahkan mode layar gabungan, khusus obat jadi, dan khusus racikan. Operator dapat membuka monitor tambahan sebanyak yang dibutuhkan dan memilih mode per monitor.
- Menambahkan kontrak API antrean farmasi di klien dan server, termasuk polling berkala dan perubahan status `MENUNGGU`, `DISIAPKAN`, dan `SIAP`.
- Menambahkan pratinjau data terkontrol hanya untuk pengambilan bukti UAT. Jalur produksi tetap membaca endpoint server dan tidak memalsukan data saat endpoint belum tersedia.
- Menormalkan respons API AIS lama yang diawali/diakhiri elemen `script`, dengan parser yang tetap fail-closed untuk HTML atau JSON rusak.
- Menambahkan skenario volume farmasi, pengadaan, pembayaran vendor, jurnal manual idempoten, dan bukti visual laporan.
- Menaikkan versi aplikasi ke `1.34.22+184` serta memastikan flavor Android Apotik menggunakan application ID `id.zishof.ebisnis.apotik`.
- Menambahkan generator data demo server yang idempoten untuk target 1.000 obat dan 1.000 racikan. Generator baru efektif setelah commit server AIS dideploy.

## Hasil UAT terverifikasi

### Pelayanan farmasi

- 50/50 transaksi obat jadi berhasil melalui API demo.
- 50/50 transaksi penebusan resep/racikan berhasil melalui API demo.
- 100 resep/racikan berhasil dibaca.
- Penerimaan PBF `UAT-TERIMA-APT-13422-001` berhasil menambah 150 unit `UJI-PCT`, batch dengan kedaluwarsa 31 Desember 2028.
- Laporan penjualan berhasil dibuka; bukti setelah run menampilkan Rp331.000, kuantitas 107, `UJI-PCT` 105/Rp315.000 dan `UJI-CDN` 2/Rp16.000.
- Laporan kedaluwarsa sukses dan mengembalikan 3 baris.
- Register obat terkendali, formularium, batch/FEFO, dashboard, kasir, resep, dan penerimaan PBF berhasil dirender sebagai bukti UAT.

### Layar pasien/keluarga

- Komponen layar gabungan, obat jadi, dan racikan berhasil dirender pada 1600×900 dengan 50 antrean terkontrol.
- Nama dan nomor rekam medis pada bukti layar publik menggunakan identitas tersamar.
- Status, loket, nomor antrean, dan panel edukasi terbaca pada ketiga mode.
- Integrasi endpoint antrean live di `demo.ecampus.id` masih BLOCKED karena commit server belum terdeploy; hasil ini adalah PASS KOMPONEN, bukan PASS integrasi.

### Procure-to-pay

- 50 PR dibuat.
- 50 PO dibuat, bergantian termin dan non-termin.
- 50 BAST dibuat/disetujui.
- 50 tagihan vendor diterima.
- 50 pembayaran vendor disetujui.
- Satu Proses Transfer ID 10 memuat 50 detail pembayaran dengan nilai total Rp45.730.000 dan berstatus disetujui.

### Akuntansi

- Workbook `cetak_data_260904124814.xlsx` diaudit: 318 baris termasuk header, 317 akun data, dan tidak ditemukan duplikasi kode pada pembacaan UAT.
- Jurnal pembayaran vendor UAT memakai Dr `310.500 HUTANG VENDOR` dan Cr `111.101 KAS YAYASAN`.
- 50 jurnal umum manual dibuat seimbang, diposting, dan diverifikasi idempoten.
- Enam halaman laporan berhasil dibuka: Laba Rugi, Neraca, Arus Kas, Keseluruhan Jurnal, Buku Besar, dan Neraca Saldo.
- Beberapa filter laporan pada bukti masih menampilkan “Belum ada data”; PASS ini membuktikan akses/render, belum merupakan validasi angka laporan.

## Pemetaan akun rujukan

| Kode | Nama akun | Penggunaan UAT |
|---|---|---|
| 111.101 | KAS YAYASAN | Kredit pembayaran vendor tunai |
| 151.200 | PERSEDIAAN BARANG LAINNYA | Persediaan obat bila kebijakan belum mempunyai subakun khusus |
| 171.200 | UANG MUKA PEMBELIAN | Uang muka/termin sebelum tagihan final |
| 310.500 | HUTANG VENDOR | Debit pelunasan kewajiban vendor |
| 310.600 | UTANG USAHA TOKO | Alternatif kewajiban toko setelah keputusan owner |
| 310.301 | HUTANG PPN | Kewajiban/utang PPN sesuai substansi |
| 410.900 | PENDAPATAN PENJUALAN TOKO | Pendapatan penjualan apotek/toko |
| 510.900 | BEBAN POKOK PENJUALAN TOKO | HPP penjualan |

Catatan kualitas sumber: kode `112,102` (CIMB) dan `121,109` (Bank Kaltim) menggunakan tanda koma. Sistem dan dokumen tidak menormalisasinya diam-diam; pemilik COA harus menetapkan bentuk yang sah.

## Quality gate

- UAT volume farmasi: PASS sesuai angka di atas.
- UAT pengadaan: PASS API 50 record per tahap.
- UAT jurnal vendor: PASS, 50 jurnal terposting.
- Uji unit baru parser respons legacy: 4/4 PASS.
- Kontrak Bantuan POS diperbarui untuk 17 topik, setiap topik minimal 3.500 kata dan sedikitnya 6 langkah workflow.
- Analisis statis: tidak ada error atau warning; terdapat 50 lint tingkat `info` yang telah ada pada area di luar perubahan rilis.
- Suite unit/widget penuh: 997/1.000 PASS pada run awal. Tiga kegagalan diisolasi: satu kontrak jumlah topik Bantuan diperbaiki pada rilis ini dan lulus pada retest; dua prasyarat workspace lama tetap ada—model ONNX wajah tidak tersedia di checkout dan satu test mencari layout repo AIS lama `../../../AIS/ais/src/main`. Keduanya bukan jalur fungsi Apotik yang diubah, tetapi tetap dicatat terbuka. Tes fokus parser, layar antrean, Bantuan, dan profil varian selanjutnya lulus 12/12.
- Build Windows release: PASS. Warning konversi numerik berasal dari dependensi native `flutter_zxing`.
- Build Android flavor `apotik`: PASS; manifest diverifikasi sebagai `id.zishof.ebisnis.apotik`, versionName `1.34.22`, versionCode `184`, dan label `eBisnis POS Apotik`. Sertifikatnya Android Debug karena keystore produksi belum tersedia.

## Batasan dan tindak lanjut wajib

1. Deploy commit server AIS yang berisi endpoint antrean farmasi dan generator demo volume; kemudian provision target katalog ≥1.000 obat serta ≥1.000 racikan secara idempoten.
2. Retest antrean live: buat 50 antrean, ubah status `MENUNGGU → DISIAPKAN → SIAP`, verifikasi seluruh monitor, privasi, polling, dan penghapusan/arsip.
3. Preview jurnal otomatis pembayaran vendor dan fixed asset di server demo belum menyediakan rincian. Implementasikan/fiksasi mapping otomatis atau sahkan SOP jurnal manual dengan approval yang sesuai.
4. Uji kulakan generik memakai akun Pedagang/kasir yang memiliki toko; akun admin demo menolak dengan “Toko tidak diketahui”. Selesaikan juga constraint sinkronisasi BAST.
5. Rekonsiliasi enam laporan pada periode dan klasifikasi akun yang benar terhadap 50 jurnal, saldo awal, buku besar, mutasi kas/bank, dan dokumen sumber; mintakan sign-off owner Akuntansi.
6. APK dibangun tanpa `android/key.properties`, sehingga memakai debug signing. Jangan distribusikan sebagai APK produksi/upgrade resmi sampai pemilik memberikan keystore dan signature telah diverifikasi.
7. Paket Windows belum memiliki Authenticode pada mesin build ini. Terapkan penandatanganan resmi sebelum deployment produksi.
8. Validasi dua kode akun bertanda koma dengan pemilik COA sebelum impor/mapping produksi.

## Dokumen dalam release

- `Manual-Pengguna-POS-Apotik-v1.34.22.docx` dan versi PDF: panduan 20 bab, use case, lima flowchart, screenshot, checklist, pemetaan akun, troubleshooting, dan batasan rilis.
- `Laporan-UAT-POS-Apotik-v1.34.22.docx` dan versi PDF: matriks hasil, bukti per alur, temuan/risiko, kriteria retest, sign-off, dan inventaris screenshot.
- `UAT-Evidence-POS-Apotik-v1.34.22.zip`: screenshot farmasi, pengadaan, akuntansi, diagram, dan ringkasan mesin.
- `SHA256SUMS.txt`: checksum seluruh aset yang dipublikasikan.

## Cara instalasi singkat

Windows: unduh ZIP desktop, verifikasi SHA-256, ekstrak seluruh isinya ke satu folder, lalu jalankan `ebisnis_apotik.exe`. Jangan menjalankan executable tanpa folder `data` dan DLL pendamping.

Android: unduh APK, verifikasi SHA-256, aktifkan pemasangan dari sumber tepercaya hanya selama instalasi, lalu nonaktifkan kembali. Karena build ini belum ditandatangani keystore produksi, gunakan hanya untuk UAT/pilot terkontrol dan jangan menimpa instalasi produksi.

Sebelum pilot, pastikan server, role/RBAC, toko aktif, printer/barcode, jam perangkat, sertifikat HTTPS, backup/rollback, dan sinkronisasi awal telah diverifikasi sesuai manual.
