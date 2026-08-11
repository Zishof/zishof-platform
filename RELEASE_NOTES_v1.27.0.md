# Release eBisnis v1.27.0

## Kulakan per-Faktur + Retur Pembelian

- **Kulakan direstrukturisasi per-Faktur**: isi Nomor Faktur, Tanggal, dan Supplier SEKALI, lalu tambahkan barang-barangnya berulang sebelum menyimpan sebagai satu transaksi. Riwayat sekarang ditampilkan per-faktur (bukan per-baris produk).
- **Supplier kini terhubung ke master Supplier** (sebelumnya cuma teks bebas) -- cari supplier yang sudah terdaftar, atau tambah cepat langsung dari layar Kulakan.
- **Input harga/jumlah menerima koma ATAU titik** sebagai pemisah desimal.
- **Total Faktur bisa diisi manual** -- bila lebih kecil dari jumlah hitungan barang, selisihnya otomatis dicatat sebagai diskon/potongan faktur.
- **Tab baru "Retur Pembelian"** di menu Kulakan -- catat barang yang dikembalikan ke supplier, stok otomatis berkurang.

## Instalasi
- **Windows**: unduh `eBisnis-Setup-1.27.0.exe` (atau `Al-Bahjah-POS-Setup-1.27.0.exe` untuk varian bermerek Al-Bahjah) dan jalankan.
- **Android**: unduh `eBisnis-1.27.0.apk` dan instal (aktifkan "izinkan dari sumber tidak dikenal" bila diminta).
