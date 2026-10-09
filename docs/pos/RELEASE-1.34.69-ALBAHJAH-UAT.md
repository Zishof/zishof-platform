# Al-Bahjah POS 1.34.69 (build 232) — UAT

Paket uji internal untuk memvalidasi perbaikan nomor nota Al-Bahjah. Source dibangun dari `main` pada commit `f933d5055833ee2bc867a9765950d017476774c9`.

## Perubahan yang dibawa

- Pembuatan nomor nota memeriksa nomor urut tertinggi yang sudah tercatat pada basis data lokal dan menghindari kode nota yang sudah tersimpan di perangkat.
- Rilis ini menyertakan semua perubahan `main` hingga commit sumber di atas.
- Server AIS memiliki perlindungan tambahan pada source SVN r92719 untuk menolak transaksi baru yang memakai nomor nota transaksi lain dengan member/nilai yang berbeda nyata. Penerapan server tidak termasuk paket ini dan belum diverifikasi pada produksi.

## Pemeriksaan

- Pengujian transaksi lokal dan pembayaran: lulus.
- Pengujian saldo struk dan peringatan transaksi: lulus.
- Pengujian database lokal/outbox: lulus.
- APK: package `id.zishof.ebisnis.albahjah`, versi `1.34.69`, versionCode `232`, nama aplikasi `Al-Bahjah POS`, tanda tangan Android Debug/UAT.
- Windows: ProductName `Al-Bahjah POS`, ProductVersion `1.34.69`, installer tanpa Authenticode/UAT.

## Status penggunaan

Ini prarilis untuk UAT/internal. Jangan dipakai sebagai bukti bahwa data lama telah diperbaiki atau server produksi telah diperbarui. Jangan mengulang transaksi nyata yang masih pending, dan jangan memasukkan pembayaran nyata untuk menguji. Rekonsiliasi nota lama dan saldo voucher harus dilakukan PIC keuangan/admin dengan mencocokkan riwayat penjualan, bukti pembayaran, serta mutasi saldo.

## Berkas dan sidik SHA-256

| Berkas | Ukuran | SHA-256 |
| --- | ---: | --- |
| `Al-Bahjah-POS-Setup-1.34.69.exe` | 90,095,544 byte | `46c60e9da3cebb9b63b6024c6eff9eb47021edabaab3bc7e20113a2faebec8f3` |
| `app-albahjah-release.apk` | 197,115,571 byte | `910e8d3aedc58f0343ebf1a5f99ae79da1e082e448e831397d495a6abc5ab022` |

## Tautan unduh

- Windows: https://github.com/Zishof/zishof-platform/releases/download/v1.34.69/Al-Bahjah-POS-Setup-1.34.69.exe
- Android: https://github.com/Zishof/zishof-platform/releases/download/v1.34.69/app-albahjah-release.apk
- Halaman prarilis: https://github.com/Zishof/zishof-platform/releases/tag/v1.34.69
