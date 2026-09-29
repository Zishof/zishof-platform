# UAT dan User Manual ABChicken POS Rev2

**Tanggal:** 29 September 2026

**Varian:** `abchicken`

**Versi:** `1.34.52+215` tanpa kenaikan versi
**Tenant:** ABChicken, toko Pusat AB Chicken

## Keputusan

Empat workbook telah dipetakan ke source dan bukti UAT live. Semua 58 kebutuhan pada Fitur DKB SmartPOS tercatat dalam satu kontrak fitur Windows dan Android. Pemeriksaan statis menemukan 370 aksi literal klien dan tidak menemukan aksi literal yang hilang dari source server yang diperiksa. Bukti live memvalidasi layar dan data utama, tetapi tidak membuktikan seluruh 58 aturan bisnis secara end to end.

Perbaikan Rev2 memulihkan identitas pengguna bersama token agar modul HRD tetap dapat membentuk cache local-first yang terpisah per tenant dan akun setelah aplikasi dibuka ulang.

## Hasil data live

| Proses | Total | Hasil |
|---|---:|---|
| Pesanan outlet | 170 | Lulus |
| Resep dan BOM | 60 | Lulus |
| PR | 170 | Lulus |
| PO | 170 | Lulus |
| BAST | 170 | Lulus |
| Tagihan vendor | 170 | Lulus |
| Pembayaran vendor | 170 | Lulus |
| Produksi dan packing | 170 | Lulus |
| Pengiriman | 270 | Lulus |
| Retur dan klaim | 120 | Lulus |
| Penjualan POS | 220 | Lulus |
| Jurnal umum | 302 | Lulus |

Laporan agregat memiliki jumlah baris sesuai struktur laporan: buku besar 302, neraca saldo 5, laba rugi 7, neraca 9, dan arus kas 5. Nilai di bawah 50 tidak ditambah dengan data palsu.

## Cakupan workbook

- Fitur DKB SmartPOS: 58 kebutuhan dipetakan ke menu dan kontrak source.
- DATA MASTER: 91 outlet internal, 16 pelanggan eksternal, 60 data packing unik, 171 data gudang pusat unik, 64 supplier packing, dan 202 supplier gudang unik.
- MASTER MENU 2026: 197 baris pada sheet DRABHAS, 181 SKU unik. Ditemukan 16 kode ganda dan 11 formula #REF!; workbook sumber perlu dikoreksi oleh pemilik data.
- Laporan Harian DR Cibanteng: 31 sheet harian dipetakan ke laporan Laporan Harian Outlet pada katalog server. Workbook tidak mengandung nilai error formula saat diperiksa.

## Batas verifikasi

- Scan source server mencakup literal aksi, bukan bukti bahwa setiap jalur mutasi berhasil pada produksi.
- UAT live dilakukan dengan akun tenant ABChicken pada server aktif dan bukti layar di folder evidence-live.
- Satu akun backoffice telah terverifikasi. Akun kasir terpisah belum diprovisioning dalam pekerjaan ini.
- Password tidak ditulis ke dokumen atau WhatsApp.
- APK bertanda DEBUG/UAT dan installer Windows belum memiliki Authenticode.

## Pemetaan 58 fitur

| ID | Departemen | Kebutuhan | Posisi menu | Bukti | Status |
|---|---|---|---|---|---|
| DKB-01 | Operational | Kasir (order & biling, menu dengan foto produk, print struk untuk customer dan dapur) | Operasional > Kasir/POS | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-02 | Operational | Nomor antrian di setiap struk, catatan pesanan | Operasional > Kasir/POS > Keranjang | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-03 | Operational | Waste produk dan retur barang | Produksi > Waste & Susut Produksi | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-04 | Operational | Manager Meal (tester maximal 20 rb) dan crew meal atau diskon karyawan (potongan harga 10 %) | Operasional > Kasir/POS > Meal Pegawai | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-05 | Operational | Laporan penjualan perjam dan per item serta menu khusus | Transaksi & Laporan > Penjualan | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-06 | Operational | Laporan mengenai laba rugi, cogs, dan sebagainya | Akuntansi > Laba Rugi | 11-pos_sale-50-record.png | UAT LAPORAN/LAYAR |
| DKB-07 | Operational | Self order/customer pesan sendiri lewat scan | Operasional > Self Order / QR Menu | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-08 | Operational | Buka dan akhiri shift otomatis | Operasional > Pengaturan Shift Otomatis | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-09 | Operational | Offline POS | Operasional > Kasir/POS | 11-pos_sale-50-record.png | SOURCE + MENU |
| DKB-10 | Research & Development | Update HPP dengan fitur all outlet atau check list toko | Master Data > Grup Produk | 02-bom-50-record.png | SOURCE + MENU |
| DKB-11 | Research & Development | Penghapusan resep dan menu sekaligus | Master Data > Produk > Resep | 02-bom-50-record.png | UAT BOM + SOURCE |
| DKB-12 | Research & Development | Penghapusan ingredient dengan fitur check list | Master Data > Produk > Resep | 02-bom-50-record.png | UAT BOM + SOURCE |
| DKB-13 | Research & Development | Custom menu dengan fitur check list | Master Data > Produk > Custom Menu | 02-bom-50-record.png | UAT BOM + SOURCE |
| DKB-14 | Research & Development | Fitur untuk melihat produk yang paling banyak dan paling sedikit terjual | Dashboard > Produk | 02-bom-50-record.png | SOURCE + MENU |
| DKB-15 | Research & Development | Laporan penjualan produk | Transaksi & Laporan > Penjualan Produk | 02-bom-50-record.png | SOURCE + MENU |
| DKB-16 | Research & Development | Laporan penjualan sales type | Transaksi & Laporan > Penjualan > Sales Type | 02-bom-50-record.png | SOURCE + MENU |
| DKB-17 | Research & Development | Semua menu dibedakan harga category termasuk online food | Master Data > Produk > Harga per Kanal | 02-bom-50-record.png | SOURCE + MENU |
| DKB-18 | Audit & Surveillance | Ringkasan Penjualan (Gross Sales, Discount, Refunds, Net Sales) | Transaksi & Laporan > Ringkasan Penjualan | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-19 | Audit & Surveillance | Gross Profit | Transaksi & Laporan > Laba Kotor | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-20 | Audit & Surveillance | Rincian Metode Pembayaran | Transaksi & Laporan > Metode Pembayaran | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-21 | Audit & Surveillance | Rincian Produk Terjual (per toko, per hari) | Transaksi & Laporan > Produk Terjual | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-22 | Audit & Surveillance | Rincian Item Refund | Transaksi & Laporan > Retur Penjualan | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-23 | Audit & Surveillance | Laporan Transaksi per hari/bulan/tahun | Transaksi & Laporan > Transaksi | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-24 | Audit & Surveillance | Laporan Shift (pemasukan dan pengeluaran) | Transaksi & Laporan > Rekonsiliasi Sesi | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-25 | Audit & Surveillance | Laporan Inventory/Stok (saldo awal, purchase order, pemakaian/usage, transfer stok, adjustment stok, waste, saldo akhir) | Inventory & Sales > Riwayat Stok | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-26 | Audit & Surveillance | Ringkasan Selisih Stok | Inventory & Sales > Rekonsiliasi Stok | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-27 | Audit & Surveillance | Ringkasan waste produk | Produksi > Waste & Susut Produksi | 20-keseluruhan-jurnal.png | UAT LAPORAN/LAYAR |
| DKB-28 | HRD | Pengajuan cuti online | SDM / HRD > Cuti & Izin | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-29 | HRD | Rekap kehadiran bisa dengan beberapa metode: foto/fingerprint/qrcode | SDM / HRD > Kehadiran | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-30 | HRD | Pengajuan Sakit dan Izin secara online, lalu ngelink approval dari atasan dan HRD | SDM / HRD > Cuti & Izin | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-31 | HRD | Terdapat grafik kedisiplinan (Paling sering izin, Paling sering datang tepat waktu) | SDM / HRD > Kedisiplinan | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-32 | HRD | Bisa tarik data riwayat kehadiran | SDM / HRD > Kehadiran | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-33 | HRD | Untuk outlet absen di Aplikasi -> setiap karyawan dibuatkan akun dan WAJIB ABSEN di aplikasi tsb | SDM / HRD > Pegawai | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-34 | HRD | 7 Pengajian dan lembur berdasarkan surat perintah/persetujuan atasan-> jika tidak ada, dianggap tidak lembur (tidak untuk pencairan lembur) | SDM / HRD > Payroll | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-35 | HRD | Jenjang kenaikan gaji disesuaikan berdasarkan masa kerja atau persentase | SDM / HRD > Payroll > Jenjang Gaji | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-36 | HRD | Bisa integrasi data kasbon dan segala bentuk potongan ke dalam slip gaji tanpa harus menginput manual | SDM / HRD > Payroll | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-37 | HRD | Sistem slip gaji mengakses mandiri di akun pribadi karyawan | SDM / HRD > Payroll > Slip Saya | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-38 | HRD | Setiap karyawan mendapatkan ID User sehingga presensi bisa ter-record | SDM / HRD > Pegawai | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-39 | HRD | 12 Setiap tim lapangan yang visit ke outlet untuk pendampingan akan mendapatkan notes minusan secara otomatis setelah mendapatkan verifikasi audit | SDM / HRD > Aturan Potongan | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-40 | HRD | Karyawan yang tercatat resign dadakan kena potong gaji 50% | SDM / HRD > Aturan Potongan | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-41 | HRD | Karyawan masa kerja di bawah 10 hari tidak kena minusan | SDM / HRD > Aturan Potongan | 34-sdm-hrd-semua-tab-lulus.png | UAT LAYAR |
| DKB-42 | Purchase | Purchase Request (dari divisi gudang, packing, bd, rpa) | Pengadaan > PR | 03-procurement_pr-50-record.png | UAT DATA 50+ |
| DKB-43 | Purchase | Laporan Purchase Request | Pengadaan > Laporan PR | 03-procurement_pr-50-record.png | UAT LAYAR/DATA |
| DKB-44 | Purchase | List Data Supplier | Master Data > Pemasok | 03-procurement_pr-50-record.png | UAT LAYAR/DATA |
| DKB-45 | Purchase | Daftar Pembelian | Inventory & Sales > Kulakan | 03-procurement_pr-50-record.png | UAT LAYAR/DATA |
| DKB-46 | Purchase | Laporan Pembelian (Persupplier, Perjenis, Peritem) | Inventory & Sales > Hutang Supplier | 03-procurement_pr-50-record.png | UAT LAYAR/DATA |
| DKB-47 | Purchase | Reminder Pembayaran Tempo | Inventory & Sales > Hutang Supplier | 03-procurement_pr-50-record.png | UAT LAYAR/DATA |
| DKB-48 | Purchase | Data Retur Supplier | Inventory & Sales > Retur Pembelian | 03-procurement_pr-50-record.png | UAT LAYAR/DATA |
| DKB-49 | Supply Chain | PO di buat oleh SPV, Business Development, RPA dan divisi lain yang akan order barang langsung link tanpa gudang input manual | Pengadaan > PO | 09-shipment-50-record.png | UAT DATA 50+ |
| DKB-50 | Supply Chain | Gudang (manager/adm) bisa edit PO untuk pengurangan barang | Pengadaan > PO | 09-shipment-50-record.png | UAT DATA 50+ |
| DKB-51 | Supply Chain | PO bisa di print dalam bentuk surat jalan (ada kolom ceklist untuk gudang, checker, dan outlet) ada kolom TTD juga untuk gudang delivery dan outlet | Distribusi & Pengiriman > Surat Jalan | 09-shipment-50-record.png | UAT DATA 50+ |
| DKB-52 | Supply Chain | Bisa menampilkan data pemakaian dan sisa stok outlet pada saat PO ke gudang | Pengadaan > PO > Riwayat Stok Outlet | 09-shipment-50-record.png | UAT DATA 50+ |
| DKB-53 | Supply Chain | Bisa tarik data laporan pengiriman barang harian, mingguan, bulanan. Baik per item/outlet | Distribusi & Pengiriman > Laporan | 09-shipment-50-record.png | UAT DATA 50+ |
| DKB-54 | Supply Chain | Data return dari outlet | Distribusi & Pengiriman > Retur Outlet | 09-shipment-50-record.png | UAT DATA 50+ |
| DKB-55 | General Affair | Pengajuan inventaris toko lewat aplikasi POS, approval ke bagian General Affair dan di acc oleh Keuangan | Inventaris GA > Pengajuan | 35-inventaris-general-affair.png | UAT LAYAR |
| DKB-56 | General Affair | List inventaris per toko | Inventaris GA > Daftar Aset | 35-inventaris-general-affair.png | UAT LAYAR |
| DKB-57 | General Affair | Pengajuan retur inventaris | Inventaris GA > Retur | 35-inventaris-general-affair.png | UAT LAYAR |
| DKB-58 | General Affair | Pengajuan perpindahan invetaris dari satu outlet ke outlet lainnya | Inventaris GA > Perpindahan | 35-inventaris-general-affair.png | UAT LAYAR |

## Petunjuk penggunaan

1. Masuk dengan akun yang berhak pada tenant ABChicken dan pilih Pusat AB Chicken.
2. Tekan Sinkronkan sebelum pengujian online dan pastikan antrean lokal tidak gagal.
3. Kasir: buka Operasional > Kasir/POS, pilih produk, isi catatan, pilih pembayaran, lalu selesaikan transaksi.
4. Rantai pasok: buka Pusat Operasi AB Chicken dan ikuti Pesanan Outlet, PR, PO, BAST, Tagihan, Pembayaran, Produksi, Pengiriman, serta Retur/Klaim.
5. HRD: buka SDM / HRD lalu pilih tab Pegawai, Cuti dan Izin, Kehadiran, Kedisiplinan, Payroll, Karier dan Gaji, Kinerja, Riwayat, atau Master HRD.
6. Laporan harian: buka Transaksi dan Laporan, pilih Laporan Harian Outlet, isi periode, lalu tekan Tampilkan.
7. Akuntansi: gunakan Draft Jurnal, Jurnal Umum, Setup Laporan, dan laporan keuangan sesuai hak akses.

## Instalasi

**Windows:** unduh installer, periksa SHA-256, jalankan sebagai pengguna berwenang, pilih More info > Run anyway bila SmartScreen menolak paket UAT, lalu buka AB Chicken POS dan sinkronkan.

**Android:** unduh APK, izinkan pemasangan dari sumber tersebut hanya untuk browser atau file manager yang dipakai, pasang APK, lalu matikan kembali izin tersebut. Jika Play Protect menolak, gunakan hanya perangkat UAT yang disetujui.

## Tautan rilis

- Android APK: https://github.com/Zishof/zishof-platform/releases/download/abchicken-v1.34.52-build215-uat-rev2-20260929/app-abchicken-release.apk
- POS Desktop: https://github.com/Zishof/zishof-platform/releases/download/abchicken-v1.34.52-build215-uat-rev2-20260929/AB-Chicken-Setup-1.34.52.exe
- Presentasi: https://github.com/Zishof/zishof-platform/releases/download/abchicken-v1.34.52-build215-uat-rev2-20260929/UAT-ABChicken-Rev2-1.34.52-20260929.pptx
- Halaman rilis: https://github.com/Zishof/zishof-platform/releases/tag/abchicken-v1.34.52-build215-uat-rev2-20260929
