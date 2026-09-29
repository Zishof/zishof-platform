# UAT dan User Manual ABChicken POS Rev3

**Format:** satu kebutuhan Fitur DKB SmartPOS per bagian dan per halaman pada PPTX, DOCX, serta PDF.

**Tanggal:** 29 September 2026

**Varian:** `abchicken`

**Versi:** `1.34.52+215` tanpa kenaikan versi

## Keputusan

Kelima puluh delapan kebutuhan pada Fitur DKB SmartPOS tercatat dalam kontrak fitur Windows dan Android. Setiap kebutuhan mempunyai halaman sendiri dengan posisi menu, fungsi, status bukti, screenshot live, dan anotasi penggunaan. Bukti SOURCE + MENU membuktikan kontrak dan posisi menu, tetapi belum membuktikan seluruh aturan bisnis secara end to end.

## Data live utama

- Pesanan outlet 170, resep dan BOM 60, PR 170, PO 170, BAST 170.
- Tagihan vendor 170, pembayaran vendor 170, produksi 170, pengiriman 270.
- Retur dan klaim 120, penjualan POS 220, jurnal umum 302, buku besar 302.
- Laporan agregat mempertahankan struktur asli: neraca saldo 5, laba rugi 7, neraca 9, arus kas 5. Data palsu tidak ditambahkan.

## Temuan kualitas workbook

- MASTER MENU 2026 memiliki 16 kode ganda dan 11 formula `#REF!` pada sheet DRABHAS.
- DATA MASTER memiliki satu kode supplier ganda dan 134 faktor konversi kosong.
- Laporan Harian DR Cibanteng memiliki 31 sheet dan tidak mengandung nilai error formula pada pemeriksaan ini.

## Pemetaan per fitur

## DKB-01 Kasir (order & biling, menu dengan foto produk, print struk untuk customer dan dapur)

- Departemen: Operational
- Posisi menu: Operasional > Kasir/POS
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-02 Nomor antrian di setiap struk, catatan pesanan

- Departemen: Operational
- Posisi menu: Operasional > Kasir/POS > Keranjang
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-03 Waste produk dan retur barang

- Departemen: Operational
- Posisi menu: Produksi > Waste & Susut Produksi
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-04 Manager Meal (tester maximal 20 rb) dan crew meal atau diskon karyawan (potongan harga 10 %)

- Departemen: Operational
- Posisi menu: Operasional > Kasir/POS > Meal Pegawai
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-05 Laporan penjualan perjam dan per item serta menu khusus

- Departemen: Operational
- Posisi menu: Transaksi & Laporan > Penjualan
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-06 Laporan mengenai laba rugi, cogs, dan sebagainya

- Departemen: Operational
- Posisi menu: Akuntansi > Laba Rugi
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-07 Self order/customer pesan sendiri lewat scan

- Departemen: Operational
- Posisi menu: Operasional > Self Order / QR Menu
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-08 Buka dan akhiri shift otomatis

- Departemen: Operational
- Posisi menu: Operasional > Pengaturan Shift Otomatis
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-09 Offline POS

- Departemen: Operational
- Posisi menu: Operasional > Kasir/POS
- Status bukti: SOURCE + MENU
- Screenshot: `11-pos_sale-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-10 Update HPP dengan fitur all outlet atau check list toko

- Departemen: Research & Development
- Posisi menu: Master Data > Grup Produk
- Status bukti: SOURCE + MENU
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-11 Penghapusan resep dan menu sekaligus

- Departemen: Research & Development
- Posisi menu: Master Data > Produk > Resep
- Status bukti: UAT BOM + SOURCE
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-12 Penghapusan ingredient dengan fitur check list

- Departemen: Research & Development
- Posisi menu: Master Data > Produk > Resep
- Status bukti: UAT BOM + SOURCE
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-13 Custom menu dengan fitur check list

- Departemen: Research & Development
- Posisi menu: Master Data > Produk > Custom Menu
- Status bukti: UAT BOM + SOURCE
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-14 Fitur untuk melihat produk yang paling banyak dan paling sedikit terjual

- Departemen: Research & Development
- Posisi menu: Dashboard > Produk
- Status bukti: SOURCE + MENU
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-15 Laporan penjualan produk

- Departemen: Research & Development
- Posisi menu: Transaksi & Laporan > Penjualan Produk
- Status bukti: SOURCE + MENU
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-16 Laporan penjualan sales type

- Departemen: Research & Development
- Posisi menu: Transaksi & Laporan > Penjualan > Sales Type
- Status bukti: SOURCE + MENU
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-17 Semua menu dibedakan harga category termasuk online food

- Departemen: Research & Development
- Posisi menu: Master Data > Produk > Harga per Kanal
- Status bukti: SOURCE + MENU
- Screenshot: `02-bom-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-18 Ringkasan Penjualan (Gross Sales, Discount, Refunds, Net Sales)

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Ringkasan Penjualan
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-19 Gross Profit

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Laba Kotor
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-20 Rincian Metode Pembayaran

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Metode Pembayaran
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-21 Rincian Produk Terjual (per toko, per hari)

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Produk Terjual
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-22 Rincian Item Refund

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Retur Penjualan
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-23 Laporan Transaksi per hari/bulan/tahun

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Transaksi
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-24 Laporan Shift (pemasukan dan pengeluaran)

- Departemen: Audit & Surveillance
- Posisi menu: Transaksi & Laporan > Rekonsiliasi Sesi
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-25 Laporan Inventory/Stok (saldo awal, purchase order, pemakaian/usage, transfer stok, adjustment stok, waste, saldo akhir)

- Departemen: Audit & Surveillance
- Posisi menu: Inventory & Sales > Riwayat Stok
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-26 Ringkasan Selisih Stok

- Departemen: Audit & Surveillance
- Posisi menu: Inventory & Sales > Rekonsiliasi Stok
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-27 Ringkasan waste produk

- Departemen: Audit & Surveillance
- Posisi menu: Produksi > Waste & Susut Produksi
- Status bukti: UAT LAPORAN/LAYAR
- Screenshot: `20-keseluruhan-jurnal.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-28 Pengajuan cuti online

- Departemen: HRD
- Posisi menu: SDM / HRD > Cuti & Izin
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-29 Rekap kehadiran bisa dengan beberapa metode: foto/fingerprint/qrcode

- Departemen: HRD
- Posisi menu: SDM / HRD > Kehadiran
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-30 Pengajuan Sakit dan Izin secara online, lalu ngelink approval dari atasan dan HRD

- Departemen: HRD
- Posisi menu: SDM / HRD > Cuti & Izin
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-31 Terdapat grafik kedisiplinan (Paling sering izin, Paling sering datang tepat waktu)

- Departemen: HRD
- Posisi menu: SDM / HRD > Kedisiplinan
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-32 Bisa tarik data riwayat kehadiran

- Departemen: HRD
- Posisi menu: SDM / HRD > Kehadiran
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-33 Untuk outlet absen di Aplikasi -> setiap karyawan dibuatkan akun dan WAJIB ABSEN di aplikasi tsb

- Departemen: HRD
- Posisi menu: SDM / HRD > Pegawai
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-34 7 Pengajian dan lembur berdasarkan surat perintah/persetujuan atasan-> jika tidak ada, dianggap tidak lembur (tidak untuk pencairan lembur)

- Departemen: HRD
- Posisi menu: SDM / HRD > Payroll
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-35 Jenjang kenaikan gaji disesuaikan berdasarkan masa kerja atau persentase

- Departemen: HRD
- Posisi menu: SDM / HRD > Payroll > Jenjang Gaji
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-36 Bisa integrasi data kasbon dan segala bentuk potongan ke dalam slip gaji tanpa harus menginput manual

- Departemen: HRD
- Posisi menu: SDM / HRD > Payroll
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-37 Sistem slip gaji mengakses mandiri di akun pribadi karyawan

- Departemen: HRD
- Posisi menu: SDM / HRD > Payroll > Slip Saya
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-38 Setiap karyawan mendapatkan ID User sehingga presensi bisa ter-record

- Departemen: HRD
- Posisi menu: SDM / HRD > Pegawai
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-39 12 Setiap tim lapangan yang visit ke outlet untuk pendampingan akan mendapatkan notes minusan secara otomatis setelah mendapatkan verifikasi audit

- Departemen: HRD
- Posisi menu: SDM / HRD > Aturan Potongan
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-40 Karyawan yang tercatat resign dadakan kena potong gaji 50%

- Departemen: HRD
- Posisi menu: SDM / HRD > Aturan Potongan
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-41 Karyawan masa kerja di bawah 10 hari tidak kena minusan

- Departemen: HRD
- Posisi menu: SDM / HRD > Aturan Potongan
- Status bukti: UAT LAYAR
- Screenshot: `34-sdm-hrd-semua-tab-lulus.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-42 Purchase Request (dari divisi gudang, packing, bd, rpa)

- Departemen: Purchase
- Posisi menu: Pengadaan > PR
- Status bukti: UAT DATA 50+
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-43 Laporan Purchase Request

- Departemen: Purchase
- Posisi menu: Pengadaan > Laporan PR
- Status bukti: UAT LAYAR/DATA
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-44 List Data Supplier

- Departemen: Purchase
- Posisi menu: Master Data > Pemasok
- Status bukti: UAT LAYAR/DATA
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-45 Daftar Pembelian

- Departemen: Purchase
- Posisi menu: Inventory & Sales > Kulakan
- Status bukti: UAT LAYAR/DATA
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-46 Laporan Pembelian (Persupplier, Perjenis, Peritem)

- Departemen: Purchase
- Posisi menu: Inventory & Sales > Hutang Supplier
- Status bukti: UAT LAYAR/DATA
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-47 Reminder Pembayaran Tempo

- Departemen: Purchase
- Posisi menu: Inventory & Sales > Hutang Supplier
- Status bukti: UAT LAYAR/DATA
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-48 Data Retur Supplier

- Departemen: Purchase
- Posisi menu: Inventory & Sales > Retur Pembelian
- Status bukti: UAT LAYAR/DATA
- Screenshot: `03-procurement_pr-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-49 PO di buat oleh SPV, Business Development, RPA dan divisi lain yang akan order barang langsung link tanpa gudang input manual

- Departemen: Supply Chain
- Posisi menu: Pengadaan > PO
- Status bukti: UAT DATA 50+
- Screenshot: `09-shipment-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-50 Gudang (manager/adm) bisa edit PO untuk pengurangan barang

- Departemen: Supply Chain
- Posisi menu: Pengadaan > PO
- Status bukti: UAT DATA 50+
- Screenshot: `09-shipment-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-51 PO bisa di print dalam bentuk surat jalan (ada kolom ceklist untuk gudang, checker, dan outlet) ada kolom TTD juga untuk gudang delivery dan outlet

- Departemen: Supply Chain
- Posisi menu: Distribusi & Pengiriman > Surat Jalan
- Status bukti: UAT DATA 50+
- Screenshot: `09-shipment-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-52 Bisa menampilkan data pemakaian dan sisa stok outlet pada saat PO ke gudang

- Departemen: Supply Chain
- Posisi menu: Pengadaan > PO > Riwayat Stok Outlet
- Status bukti: UAT DATA 50+
- Screenshot: `09-shipment-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-53 Bisa tarik data laporan pengiriman barang harian, mingguan, bulanan. Baik per item/outlet

- Departemen: Supply Chain
- Posisi menu: Distribusi & Pengiriman > Laporan
- Status bukti: UAT DATA 50+
- Screenshot: `09-shipment-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-54 Data return dari outlet

- Departemen: Supply Chain
- Posisi menu: Distribusi & Pengiriman > Retur Outlet
- Status bukti: UAT DATA 50+
- Screenshot: `09-shipment-50-record.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-55 Pengajuan inventaris toko lewat aplikasi POS, approval ke bagian General Affair dan di acc oleh Keuangan

- Departemen: General Affair
- Posisi menu: Inventaris GA > Pengajuan
- Status bukti: UAT LAYAR
- Screenshot: `35-inventaris-general-affair.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-56 List inventaris per toko

- Departemen: General Affair
- Posisi menu: Inventaris GA > Daftar Aset
- Status bukti: UAT LAYAR
- Screenshot: `35-inventaris-general-affair.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-57 Pengajuan retur inventaris

- Departemen: General Affair
- Posisi menu: Inventaris GA > Retur
- Status bukti: UAT LAYAR
- Screenshot: `35-inventaris-general-affair.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## DKB-58 Pengajuan perpindahan invetaris dari satu outlet ke outlet lainnya

- Departemen: General Affair
- Posisi menu: Inventaris GA > Perpindahan
- Status bukti: UAT LAYAR
- Screenshot: `35-inventaris-general-affair.png`
- Anotasi: 1 kelompok menu, 2 area filter atau kontrol, 3 daftar data atau aksi.
- Petunjuk: buka posisi menu di atas, pilih tenant dan toko yang benar, gunakan filter yang diperlukan, jalankan aksi sesuai kewenangan, lalu periksa status atau data hasilnya.

## Instalasi dan tautan rilis

- APK Android: https://github.com/Zishof/zishof-platform/releases/download/abchicken-v1.34.52-build215-uat-rev3-20260929/app-abchicken-release.apk
- POS Desktop: https://github.com/Zishof/zishof-platform/releases/download/abchicken-v1.34.52-build215-uat-rev3-20260929/AB-Chicken-Setup-1.34.52.exe
- Presentasi: https://github.com/Zishof/zishof-platform/releases/download/abchicken-v1.34.52-build215-uat-rev3-20260929/UAT-ABChicken-Rev3-Per-Fitur-1.34.52-20260929.pptx
- Halaman rilis: https://github.com/Zishof/zishof-platform/releases/tag/abchicken-v1.34.52-build215-uat-rev3-20260929

APK menggunakan sertifikat DEBUG/UAT dan installer Windows belum memiliki Authenticode. Gunakan hanya pada perangkat uji yang disetujui. Password tidak dicantumkan dalam dokumen.
