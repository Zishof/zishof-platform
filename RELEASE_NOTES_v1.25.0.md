# Release eBisnis v1.25.0

## Fase 2 Stretch: Promo lanjutan + perbaikan bug "Semua Produk"

- **Perbaikan bug kritis**: toggle "Berlaku Untuk Semua Produk" di layar Diskon sebelumnya **selalu gagal disimpan** (error sistem generik). Sekarang tersimpan dengan benar, dan diskon "semua produk" ikut terpotong otomatis saat checkout.
- **Harga Coret**: kartu produk di Kasir kini menampilkan harga asli dicoret + harga promo untuk produk yang sedang didiskon publik -- pembeli langsung tahu ada potongan sebelum ditambah ke keranjang.
- **Aktivasi Manual**: admin bisa membuat promo yang tidak otomatis aktif -- kasir memilihnya sendiri lewat tombol "Promo" baru di Kasir saat pelanggan memenuhi syarat, cocok untuk promo yang perlu ditawarkan manual (bukan auto-apply ke semua transaksi yang cocok).

## Ada Kembalian (Cara Pembayaran)

- Cara Pembayaran (mis. Tunai/QRIS/Kartu) kini punya pengaturan baru "Ada Kembalian" di layar CRUD Cara Pembayaran. Default otomatis "Ya" untuk metode bernama mengandung "Tunai", "Tidak" untuk metode lain -- bisa diubah manual.
- Saat metode bayar **tidak** ada kembalian dipilih di Kasir, kolom "Uang Diterima"/kembalian disembunyikan -- pembayaran harus pas sesuai total belanja, tanpa proses hitung kembalian.

## Perbaikan lain

- Kunci toko per-akun kini konsisten: akun yang di-set ke toko tertentu (lewat pengaturan akun pengguna) tidak lagi bisa berpindah ke toko lain di Kasir maupun Stok Opname -- berlaku otomatis, tidak perlu perubahan di aplikasi ini.

> Catatan: fitur ini butuh restart server AIS untuk aktif penuh di sisi server (kolom baru dibuat otomatis oleh Hibernate saat startup).

## Instalasi
- **Windows**: unduh `eBisnis-Setup-1.25.0.exe` (atau `Al-Bahjah-POS-Setup-1.25.0.exe` untuk varian bermerek Al-Bahjah) dan jalankan.
- **Android**: unduh `eBisnis-1.25.0.apk` dan instal (aktifkan "izinkan dari sumber tidak dikenal" bila diminta).
