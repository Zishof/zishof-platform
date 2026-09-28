# v1.34.51 build 214 - rebuild Windows Al-Bahjah dan TokoQu An Nahl

Rilis ini menaikkan versi aplikasi dari `1.34.50+213` menjadi `1.34.51+214`
dan membangun ulang installer Windows untuk varian:

- Al-Bahjah POS
- TokoQu Al-Bahjah An Nahl

## Validasi build

Perintah build:

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_semua_varian.ps1 -SkipAndroid -Hanya albahjah,nahl -IzinkanUnsignedWindows
```

Hasil: lulus, 2 artefak berhasil dibuat.

Installer Windows berhasil dibuat dan diverifikasi sebagai `UNSIGNED/UAT` karena
sertifikat Authenticode produksi tidak tersedia di sesi ini. APK Android tidak
dibangun pada rilis ini.

## Artefak Windows

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.51/` dan
tidak disimpan di Git.

| Varian | Installer | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.51.exe` | 89.921.385 byte | `8361c911951498354050a24affb9268a79ec2dc74558fae9ed1b4e7182f00ee2` |
| TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.51.exe` | 90.056.722 byte | `f968c7cfd100c5a2105a607f98da8d76e37122d8ee46a5071ebd5429e20f087d` |

## Status paket

Build release bukan bukti pemasangan produksi atau UAT pengguna. Publikasi GitHub
tidak mengubah perangkat maupun server secara otomatis.
