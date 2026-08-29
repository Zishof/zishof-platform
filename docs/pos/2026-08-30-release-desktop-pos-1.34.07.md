# Rilis POS Desktop dan Android 1.34.07 — eBisnis, Al-Bahjah, dan Nahl

Tanggal: 30 Agustus 2026

Versi aplikasi: `1.34.07+170`

Varian: `ebisnis`, `albahjah`, `nahl`

Tag GitHub: `v1.34.07-build170`

## Ringkasan

- Seluruh unggahan foto master memakai antrean local-first bersama. Gangguan server tidak membatalkan penyimpanan lokal; pengiriman dicoba ulang secara periodik.
- Foto member, produk, dan screensaver yang masih `PENDING` atau `GAGAL` dipulihkan dari antrean lokal ketika form edit dibuka kembali, sehingga preview tidak menunggu URL server.
- Penghapusan foto membersihkan referensi lokal yang sesuai agar foto lama tidak muncul kembali.
- Daftar produk dan jalur master offline membaca cache SQLite per halaman. Snapshot puluhan ribu produk tidak lagi dibentuk seluruhnya di thread UI sebelum 15 baris pertama tampil.
- Pencarian, kategori, UOM, dan dropdown produk menormalisasi serta mendeduplikasi referensi agar form edit tidak gagal karena nilai ganda atau nilai lama yang belum ada di daftar terbaru.
- Riwayat CRUD lintas master tersedia dari audit server, termasuk jenis perubahan, nama field, nilai sebelum, dan nilai sesudah. Produk dan pelanggan mempunyai pintasan riwayat kontekstual.
- Pesan kegagalan sinkronisasi dan penyimpanan menjelaskan apakah data sudah aman di perangkat, masih menunggu kirim, atau memerlukan tindakan admin.
- Label bisnis pelanggan dikembalikan menjadi **Pengajuan Melebihi Limit** sesuai kontrak UAT.

## UAT dan kompilasi

- Seluruh `561` pengujian aplikasi eBisnis/Al-Bahjah/Nahl lulus.
- Analisis penuh menemukan `0` error kompilasi. Terdapat `53` temuan lama: `52` info gaya/depresiasi dan `1` warning cast tidak perlu.
- Ketiga APK Android berhasil dibangun dengan `versionName 1.34.07` dan `versionCode 170`.
- Ketiga installer Windows berhasil dibangun dan mempunyai `ProductVersion 1.34.07`.
- APK Android menggunakan sertifikat **Android Debug** atas persetujuan eksplisit untuk UAT internal; paket ini bukan artefak produksi/Play Store.
- Ketiga installer Windows berstatus Authenticode `NotSigned`; rilis ini untuk distribusi internal/UAT.
- SHA-256 dihitung ulang dari keenam artefak final.

## Artefak Desktop Windows

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.07.exe` | 85.792.949 byte | `390820CE91155BA8CB7661F18E30E51834FE174E210D175C85C563B1E9D94099` |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.07.exe` | 85.860.491 byte | `B19D254E135B3B31A7F6E185C6C803DA1A7D25FBA18D8B6BA23ACA817344D7AC` |
| Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.07.exe` | 85.920.404 byte | `D917CA9F0CD813444F44AA0F8CFB6368F7B2BEE6FC1A1DEFF9C0C7847FC094F5` |

## Artefak Android Debug/UAT

| Varian | Package ID | APK | Ukuran | SHA-256 |
|---|---|---|---:|---|
| eBisnis | `id.zishof.ebisnis` | `app-ebisnis-release.apk` | 189.231.798 byte | `C27387FAAD0D35BA56EF09B725F915E6DF882F231C2706F68496FD438FAFEC55` |
| Al-Bahjah | `id.zishof.ebisnis.albahjah` | `app-albahjah-release.apk` | 189.292.851 byte | `62D41AC3BEBBAB29D74FD6FF899AD76180271970D03CAC55FE29AED5F84EA43D` |
| Nahl | `id.zishof.ebisnis.nahl` | `app-nahl-release.apk` | 188.822.711 byte | `9568565733A88597C223EC632C0EFAE3F0E68046582F02ADF2DB1F8FC2B3D5AB` |

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.07/`

## UAT pengguna setelah pembaruan

> APK Android pada rilis ini khusus UAT internal. Jika perangkat sudah memasang package ID yang sama dengan sertifikat berbeda, Android akan menolak pembaruan langsung. Jangan menghapus aplikasi atau data operasional sebelum memastikan transaksi pending aman.

1. Pastikan transaksi pending sudah diperiksa sebelum memasang pembaruan. Jangan menghapus database lokal.
2. Pasang varian yang sesuai dengan toko, lalu buka Produk dan Pelanggan untuk memastikan halaman pertama tampil tanpa menunggu seluruh snapshot master.
3. Edit data dan unggah foto. Setelah status **Tersimpan di perangkat** muncul, tutup dan buka kembali form; preview foto harus tetap tersedia meski server belum menerima unggahan.
4. Buka **Sistem → Riwayat Sinkronisasi** untuk memantau antrean. Data yang masih menunggu server tidak perlu diinput ulang.
5. Uji Riwayat CRUD pada Produk dan Pelanggan; pastikan perubahan menampilkan field serta nilai sebelum dan sesudah.
6. Jika server menolak sinkronisasi secara permanen, buka Detail Error dan kirim kode referensi kepada admin. Jangan menghapus antrean lokal secara manual.

## Ketergantungan backend

Local-first menjamin perubahan tetap tercatat di perangkat, tetapi penerimaan akhir tetap memerlukan endpoint server yang sesuai. Jika endpoint unggah foto atau master belum tersedia, status akan tetap menunggu dan dicoba ulang setelah backend diperbaiki. Aturan backend tetap melarang cast native Hibernate bergaya PostgreSQL `::TYPE`; gunakan `CAST(... AS TYPE)`.

Backend tidak dikemas menjadi WAR dalam rilis aplikasi ini dan dideploy terpisah oleh admin.

## Rollback

- Hentikan rollout bila aplikasi tidak dapat dibuka, data lokal tidak dapat dibaca, atau fungsi kasir utama terganggu.
- Kembalikan ke GitHub Release `v1.34.06-build169`.
- Jangan menghapus database lokal, transaksi pending, outbox master, atau cache foto saat rollback.
