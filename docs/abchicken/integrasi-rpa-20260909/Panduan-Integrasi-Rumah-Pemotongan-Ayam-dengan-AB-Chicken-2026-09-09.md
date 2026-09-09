# Panduan Integrasi Rumah Pemotongan Ayam dengan AB Chicken

**Status dokumen:** baseline desain integrasi dan rencana implementasi. Dokumen ini bukan bukti bahwa modul Rumah Pemotongan Ayam sudah lulus UAT.

## Keputusan utama

Operasional harian dijalankan melalui POS Desktop varian `abchicken`. Aplikasi Web dipakai admin utama untuk registrasi tenant, konfigurasi, pemantauan, audit, dan penanganan pengecualian administratif. Tenant tetap `abchiken`, mode `TENANT_ONLY`, schema transaksi `abchiken`, dan schema audit `abchiken__audit`.

Jika RPA dan Gudang Pusat berada dalam satu badan hukum, perpindahan daging dicatat sebagai transfer persediaan antarlokasi. Jika keduanya berbeda badan hukum, gunakan PO, penjualan, piutang, hutang, dan eliminasi intercompany. Keputusan ini wajib dikunci sebelum implementasi jurnal.

## Siklus operasional

1. Gudang Pusat menghitung kebutuhan dan membuat PR.
2. PR yang disetujui membentuk PO internal kepada RPA.
3. RPA menerima pesanan dan menjadwalkan pemenuhan.
4. Ayam hidup datang dari peternak, ditimbang, diperiksa, dan direkam per flock/lot.
5. RPA menjalankan batch pemotongan; sistem merekam input, karkas, potongan, produk samping, susut, reject, serta limbah.
6. Produk yang lolos QC masuk persediaan dingin RPA.
7. Transaksi pemenuhan dilakukan di POS Desktop RPA dan membentuk Delivery Order.
8. Pengiriman mencatat kendaraan, pengemudi, segel, waktu, dan suhu.
9. Gudang Pusat melakukan BAST berdasarkan lot, berat tangkap, kondisi, dan selisih.
10. Stok gudang bertambah, klaim/backorder dibuat bila perlu, lalu siklus kebutuhan berikutnya dimulai.

## Prinsip data dan API

- Nama layanan dan kelas server harus generik, misalnya `supply_network`, `slaughter_batch`, dan `coldchain_delivery`; jangan menanam nama AB Chicken pada kelas domain Java.
- Semua tabel transaksi berada pada schema tenant aktif dan seluruh audit berada pada `abchiken__audit`.
- Daftar POS Desktop bersifat local-first dan dipaginasi. Approval, posting, perubahan status irreversible, dan validasi saldo tetap online-only.
- Setiap aksi memakai idempotency key dan version check untuk mencegah duplikasi dan lost update.
- Ketertelusuran wajib utuh dari peternak/flock sampai lot daging, Delivery Order, BAST Gudang, produksi outlet, dan penjualan pelanggan.

## Gerbang UAT rencana RPA

Siapkan sekurang-kurangnya 50 record bernilai pada setiap halaman proses: PR, PO internal, penerimaan ayam, QC, batch pemotongan, hasil produksi, transaksi POS/transfer, Delivery Order, pengiriman, BAST Gudang, klaim, persediaan, jurnal, dan laporan. Seluruh status, kuantitas, lot, dan jurnal harus dapat ditelusuri tanpa halaman kosong. Status LULUS baru boleh diberikan setelah aksi dilakukan dari POS Desktop dan hasil dibaca kembali dari server.
