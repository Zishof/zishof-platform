# Kasir: Sinkronkan Produk, Tambah Produk Cepat, dan Sinkron Metode Bayar

Tanggal: 30 Agustus 2026  
Pemicu: dua laporan lapangan toko Al-Bahjah (barcode `8998866200813` ke-scan
tetapi "Tidak ada produk cocok"; metode "Kasbon Divisi" tidak tampil untuk
member setelah admin mengubah izin).

## 1. Dropdown pencarian kasir yang kosong kini menawarkan aksi

Saat pencarian/scan tidak menemukan produk, dropdown menampilkan dua tombol:

- **Sinkronkan Produk** — menarik ulang seluruh katalog server ke cache lokal
  lewat `SinkronisasiTabelService.sinkronkan('produk_cache')` (jalur yang
  sama dgn menu Sinkronisasi), lalu mengulang pencarian kata yang sedang
  diketik. Untuk kasus produk baru dibuat admin tetapi cache perangkat kasir
  belum tahu.
- **Tambah produk ini** — dialog cepat (barcode terkunci dari hasil scan,
  nama*, harga jual*, kategori opsional) yang menyimpan `produk_simpan` ke
  antrean lokal terlebih dahulu. Jika server langsung memberi ID, produk masuk
  `produk_cache` dan keranjang. Jika server offline/bermasalah, draf tetap aman
  di menu Produk dan dikirim ulang otomatis; produk belum masuk keranjang agar
  ID sementara tidak pernah bocor ke transaksi. Stok awal 0 — toko yang
  melarang stok minus tetap harus mencatat
  stok lewat Produk/Kulakan sebelum bisa menjual (gerbang stok yang ada tidak
  dilonggarkan). Hak akses `produk_simpan` tetap ditegakkan server.

## 2. Server: barcode produk unik per toko (backend AIS)

`KantinHelper.produkSimpan` sebelumnya hanya menolak (a) kombinasi
kode+barcode+nama duplikat dan (b) barcode produk yang bentrok dgn barcode
KEMASAN produk lain — dua produk BEDA NAMA masih boleh ber-barcode sama,
membuat scan kasir ambigu. Kini ditambah cek eksplisit: barcode produk yang
sama dgn barcode produk lain **di toko yang sama** ditolak (status 91) dengan
pesan "Barcode ... sudah dipakai produk lain di toko ini. Barcode yang sama
hanya boleh dipakai toko berbeda." Toko berbeda sengaja tetap boleh — sesuai
permintaan pemilik produk. Verifikasi: kompilasi `javac` lulus (exit 0).

Catatan deployment: perubahan ini di `KantinHelper.java` (SVN backend) —
berlaku setelah class hasil kompilasi dipasang ke server dan Tomcat
di-restart; klien lama pun otomatis terlindungi karena validasinya di server.

## 3. Sheet split metode pembayaran: tombol "Sinkronkan cara pembayaran"

Sheet pemilih metode SUDAH memuat ulang izin dari server setiap kali dibuka;
tombol ini menambah jalur muat ulang **tanpa menutup sheet** — untuk kasus
admin mengubah izin member (mis. menambahkan Kasbon Divisi) ketika sheet
sedang terbuka di kasir. Slot terpilih yang metodenya sudah dicabut admin
ikut dibuang supaya kasir tidak membayar dgn metode yang tidak lagi
diizinkan.

## Penjaga

`test/kasir_produk_cepat_kontrak_test.dart` (2 test source-contract) mengunci
ketiga perilaku di sisi Flutter; sisi server diverifikasi kompilasi dan akan
tercakup UAT lapangan berikutnya (coba simpan dua produk ber-barcode sama di
satu toko -> harus ditolak; di dua toko berbeda -> boleh).
