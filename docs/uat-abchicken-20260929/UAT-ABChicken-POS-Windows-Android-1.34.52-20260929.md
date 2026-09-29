# UAT AB Chicken POS Windows dan Android 29 September 2026

Dokumen ini mencatat hasil verifikasi varian `abchicken` versi `1.34.52+215` dari commit Git `2f69465`.

## Status ringkas

- Build Android berhasil dan menghasilkan `app-abchicken-release.apk` dengan sertifikat debug untuk UAT.
- Build Windows berhasil dan menghasilkan `AB-Chicken-Setup-1.34.52.exe` tanpa Authenticode untuk UAT.
- 93 pengujian terarah AB Chicken, local-first, tenant, menu, HRD, dan pembayaran offline lulus.
- Gerbang data live POS Desktop lulus. Semua daftar transaksi utama memuat minimal 50 data dan tidak kosong.
- Gerbang laporan live POS Desktop lulus. Jurnal Umum dan Buku Besar masing-masing memuat 302 baris. Laporan agregat memuat 5 sampai 9 baris karena satu baris mewakili kelompok akun, bukan transaksi mentah.
- Suite penuh menghasilkan 955 lulus dan 10 gagal pada kontrak lintas-repositori terhadap source Java AIS lokal. Kegagalan tersebut dicatat sebagai temuan baseline dan membuat paket ini berstatus prarilis UAT, belum rilis produksi final.
- Android berhasil dibangun, tetapi smoke test pada perangkat fisik belum dapat dilakukan karena tidak ada perangkat ADB yang terhubung pada sesi ini.

## Volume data live

| Proses | Total |
| --- | ---: |
| Pesanan Outlet | 170 |
| Resep dan BOM | 60 |
| Permintaan Pembelian | 170 |
| Pesanan Pembelian | 170 |
| BAST Gudang Pusat | 170 |
| Terima Tagihan Vendor | 170 |
| Pembayaran Vendor | 170 |
| Produksi dan Packing | 170 |
| Delivery Order dan Pengiriman | 270 |
| Backorder Retur dan Klaim | 120 |
| Penjualan POS | 220 |
| Jurnal Umum | 302 |
| Buku Besar | 302 |

## Bukti layar dan petunjuk

Setiap gambar berikut berasal dari eksekusi aplikasi POS Desktop terhadap tenant live AB Chicken pada 29 September 2026. Tombol utama berada pada deretan tab di bawah judul. Kolom pencarian menyaring nomor dokumen, outlet, vendor, atau kata kunci. Filter Status dan Status posting membatasi daftar. Pilih satu kartu/baris untuk membuka detail dan aksi sesuai hak pengguna.

1. [Ringkasan gerbang data](evidence/00-ringkasan-data-settle.png)
2. [Pesanan Outlet 170 data](evidence/01-outlet_order-50-record.png)
3. [Resep dan BOM 60 data](evidence/02-bom-50-record.png)
4. [Permintaan Pembelian 170 data](evidence/03-procurement_pr-50-record.png)
5. [Pesanan Pembelian 170 data](evidence/04-procurement_po-50-record.png)
6. [BAST Gudang Pusat 170 data](evidence/05-procurement_bast-50-record.png)
7. [Terima Tagihan Vendor 170 data](evidence/06-procurement_invoice-50-record.png)
8. [Pembayaran Vendor 170 data](evidence/07-procurement_payment-50-record.png)
9. [Produksi dan Packing 170 data](evidence/08-production-50-record.png)
10. [Pengiriman 270 data](evidence/09-shipment-50-record.png)
11. [Retur dan Klaim 120 data](evidence/10-claim-50-record.png)
12. [Penjualan POS 220 data](evidence/11-pos_sale-50-record.png)
13. [Sumber akun posting](evidence/12-sumber-akun-posting.png)
14. [Jurnal Umum 302 baris](evidence/20-keseluruhan-jurnal.png)
15. [Halaman terakhir Jurnal Umum](evidence/20-keseluruhan-jurnal-halaman-terakhir.png)
16. [Buku Besar 302 baris](evidence/21-buku-besar.png)
17. [Neraca Saldo](evidence/22-neraca-saldo.png)
18. [Laba Rugi](evidence/23-laba-rugi.png)
19. [Neraca](evidence/24-neraca.png)
20. [Arus Kas](evidence/25-arus-kas.png)

## Instalasi Windows

1. Unduh installer dari GitHub Release AB Chicken.
2. Cocokkan SHA-256 dengan berkas pendamping.
3. Jalankan installer dengan akun Windows yang diizinkan memasang aplikasi.
4. Jika Windows SmartScreen memperingatkan penerbit tidak dikenal, pilih `More info` lalu `Run anyway` hanya setelah nama berkas dan SHA-256 cocok dengan rilis ini.
5. Buka AB Chicken, masuk memakai akun uji yang dibagikan melalui kanal aman, pilih tenant AB Chicken dan toko Pusat AB Chicken, lalu tekan Sinkronkan.

## Instalasi Android

1. Unduh APK dari GitHub Release AB Chicken.
2. Cocokkan SHA-256 dengan berkas pendamping.
3. Izinkan pemasangan dari sumber aplikasi yang dipakai mengunduh file hanya selama proses instalasi.
4. Buka APK dan pilih Install. Jika Play Protect memberi peringatan, lanjutkan hanya pada perangkat UAT setelah nama paket dan SHA-256 cocok.
5. Setelah selesai, cabut kembali izin instalasi dari sumber tidak dikenal.
6. Masuk memakai akun uji yang dibagikan melalui kanal aman, pilih tenant dan toko yang sama, lalu lakukan sinkronisasi awal.

## Batasan rilis

Paket ini memakai APK debug-signed dan installer Windows unsigned. Gunakan hanya untuk UAT internal. Kredensial tidak disimpan di repository, dokumen, atau GitHub Release. Publikasi GitHub tidak menerapkan perubahan ke server produksi.
