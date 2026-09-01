# 66. Uji Internal 1.34.17 — APK Bertanda Tangan Debug

Tanggal: 2 September 2026  
Versi: `1.34.17+179` (naik dari `1.34.16+178`)  
Tujuan: Fikri menguji tab **Rincian Produk** dan **Rekap per produk** (dok. 64,
dok. 65) langsung di HP, sebelum rilis produksi

## Status tanda tangan — baca sebelum membagikan

APK ini **ditandatangani sertifikat Android Debug** (`CN=Android Debug`), dibuat
dengan opsi eksplisit `-IzinkanDebugSigning`. Konsekuensinya:

- **Tidak dapat dipasang menimpa aplikasi produksi** di perangkat yang sama.
  Android menolak pembaruan bila tanda tangannya berbeda; aplikasi lama harus
  dicopot lebih dulu, dan **mencopot berarti menghapus data lokal aplikasi**
  (termasuk antrean transaksi offline yang belum terkirim).
- Sebagian perangkat menampilkan peringatan pemasangan dari sumber tidak dikenal.
- **Bukan untuk dibagikan ke pengguna toko.** Ini artefak uji internal.

Cara aman menguji: pakai perangkat yang tidak dipakai berjualan, atau copot
aplikasi produksi hanya setelah memastikan tidak ada transaksi offline yang
belum tersinkron.

## Temuan yang menyertai

Pemeriksaan sertifikat pada rilis sebelumnya menunjukkan
`release-artifacts/semua-varian/1.34.16/app-nahl-release.apk` **juga**
bertanda tangan `CN=Android Debug`. Jadi APK di folder rilis 1.34.16 pun bukan
artefak produksi. Selama `android/key.properties` beserta keystore-nya belum
tersedia di mesin build, **tidak ada APK produksi yang bisa dihasilkan** —
penjagaan `tool/verify_apk_signing.ps1` memang menolak build yang debug-signed
kecuali diminta secara eksplisit, dan penolakan itu benar.

Keputusan yang masih menunggu pemilik: sediakan keystore produksi (disimpan di
luar repositori, dengan cadangan yang aman — kehilangan keystore berarti
aplikasi tidak pernah bisa diperbarui lagi di perangkat yang sudah memasangnya),
atau tetapkan bahwa distribusi APK memang lewat jalur internal saja.

## Isi versi 1.34.17

- Tab **Rincian Produk** pada Laporan Transaksi: satu baris per produk pada tiap
  transaksi, dengan Preview/PDF/Excel/Word (dok. 64).
- Filter **produk** dan **kasir** pada tab itu, ikut terbawa ke hasil unduhan.
- Mode **Rekap per produk**: qty, jumlah transaksi, dan total per produk,
  dirangkum dari baris rincian yang sama (dok. 65).

Perbaikan laporan **web** (baris dibatalkan, identitas kasir, produk terhapus)
dan saklar UOM di layar Konfigurasi ada di sisi server — berlaku setelah build
server dipasang dan Tomcat di-restart, tanpa memerlukan rilis aplikasi.

## Bukti sebelum build

| Uji | Hasil |
| --- | --- |
| `TesLaporanWeb` | 10/10 |
| `TesRincianProduk` | 18/18 |
| Seluruh suite Flutter | 600/600 |
| `flutter analyze` | bersih |
