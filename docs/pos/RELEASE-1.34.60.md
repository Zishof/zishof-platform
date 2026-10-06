# v1.34.60 build 223 - rebuild Windows Al-Bahjah dan TokoQu An Nahl

Rilis ini sudah mengambil pembaruan Git terbaru dari `origin/main`, lalu menaikkan
versi aplikasi dari `1.34.59+222` menjadi `1.34.60+223` dan membangun ulang
installer Windows untuk varian:

- Al-Bahjah POS
- TokoQu Al-Bahjah An Nahl

## Ringkasan Perubahan

1. **Pelanggan > Topup - Template Excel**
   - Menambahkan tombol **Template Excel** pada tab Topup untuk akun yang
     memiliki hak `Boleh Entry Topup`.
   - Template dapat diunduh untuk semua member, berdasarkan Jenis Member, atau
     berdasarkan Tipe Member.
   - File template memakai format upload topup yang sama dengan kolom:
     `ID_MEMBER`, `KODE_MEMBER`, `NAMA_MEMBER`, `NOMINAL`, `WAKTU`,
     `TANGGAL_EXPIRED`, `METODE_PEMBAYARAN`, dan `KETERANGAN`.
   - Kolom identitas member otomatis terisi, sedangkan kolom topup lain
     dibiarkan kosong agar operator mengisi nominal dan keterangan sesuai bukti.

2. **Pembaruan dari rilis terbaru**
   - Memuat pembaruan rilis sampai `origin/main` versi `1.34.59+222`, termasuk
     perbaikan cetak thermal, ekspor rincian penerimaan member, pemulihan
     konteks sesi, navigasi laporan transaksi, dan pembaruan laporan produksi.
   - Konflik pada Rincian Produk diselesaikan dengan mempertahankan kolom
     **Kasir** dan **Metode Bayar** serta label metode pembayaran terbaru.

## Validasi

Perintah test:

```powershell
flutter test test/simple_xlsx_test.dart test/navigasi_laporan_transaksi_test.dart test/penerimaan_member_export_test.dart
```

Hasil: lulus, 13 test.

Perintah build:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_semua_varian.ps1 -Hanya albahjah,nahl -SkipAndroid -IzinkanUnsignedWindows
```

Hasil: lulus, 2 artefak Windows berhasil dibuat.

Installer Windows berhasil dibuat dan diverifikasi sebagai `UNSIGNED/UAT` karena
sertifikat Authenticode produksi tidak tersedia di sesi ini. APK Android tidak
dibangun pada rilis ini.

## Artefak Windows

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.60/` dan
tidak disimpan di Git.

| Varian | Installer | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah POS | `Al-Bahjah-POS-Setup-1.34.60.exe` | 89.939.572 byte | `4f81a47a19e3965f5b5eb4da87f7b1830d4e542de704417416ffbe5b0cabb138` |
| TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.60.exe` | 90.078.991 byte | `4c0fd868fd6be9cc7fe3300e7b33f1b6c68f97e93b137f095f0ba1b4954a5256` |

## Status Paket

Build release bukan bukti pemasangan produksi atau UAT pengguna. Publikasi source
dan artefak lokal tidak mengubah perangkat maupun server secara otomatis.
