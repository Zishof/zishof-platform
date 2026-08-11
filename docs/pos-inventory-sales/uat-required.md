# UAT Required — keputusan yang membutuhkan pengguna lama / pemilik bisnis

Daftar hal yang TIDAK boleh diputuskan sepihak oleh implementasi dan wajib dikonfirmasi
saat UAT (lihat juga assumption-register.md):

1. **Mapping No. Perkiraan sales legacy → COA existing** (layar 07). Akun yang tidak ada
   di COA target dibiarkan nullable + exception queue, bukan dikarang.
2. **Semantik "Sales Membawa Nota"** (layar 39-40): apakah satu paket nota = satu SPJ,
   aturan pengembalian nota gagal tagih, dan siapa penerima sah saat serah-terima balik.
3. **Nomor dokumen**: apakah bisnis menghendaki nomor Nota Sales TERPISAH dari nomor SPJ
   (`SPJ-SLS/{KODE_TOKO}/{YYYYMM}/{seq}`) atau satu nomor untuk keduanya.
4. **Overpayment collection**: default DITOLAK; aktifkan customer-deposit hanya bila
   pemilik menyetujui (ERD §9.2).
5. **Dispatch offline**: default WAJIB online; bila bisnis minta dispatch offline, perlu
   allocation-block stok yang diterbitkan server (PERINTAH_MASTER §13.3).
6. **Threshold approval biaya sesi** (nilai rupiah di atas berapa perlu approve owner).
7. **Kebijakan periode tutup buku** untuk posting mundur (layar 43-48).
8. **Rekonsiliasi data DBF legacy** (SUPPLIER/BELI/TRAN_HUT/masterbl): cut-off migrasi dan
   perlakuan record orphan (kode dipakai transaksi tapi master hilang → placeholder nonaktif).
9. **Perilaku runtime legacy yang hanya terlihat di video** (`Sistem Sales.mp4` tidak
   tersedia lokal saat audit) — verifikasi alur layar 39-42 bersama operator lama.
10. **UAT hardware**: printer thermal/A4 di Windows, share/print Android, scanner USB/kamera
    (P7) — perlu perangkat fisik pengguna.
11. **Keystore signing Android produksi** (P1/FND-003): build.gradle sudah membaca
    `android/key.properties` (tidak di-commit) bila tersedia; TANPA file itu release masih
    debug-signing (perilaku lama). Pemilik harus menyediakan/menyetujui keystore — TIDAK
    digenerate sepihak oleh build machine.
12. **Aset branding varian** (P1/FND-004): ikon `assets/images/inventory_sales/icon.png` dan
    `windows/runner/resources/icon_inventory_sales.ico` sementara SALINAN logo eBisnis —
    logo final varian Inventory & Sales menunggu keputusan pemilik.
