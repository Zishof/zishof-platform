# v1.34.52 build 215 - rebuild Windows Al-Bahjah dan TokoQu An Nahl

Rilis ini menaikkan versi aplikasi dari `1.34.51+214` menjadi `1.34.52+215`
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

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.52/` dan
tidak disimpan di Git.

| Varian | Installer | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.52.exe` | 89.919.928 byte | `78623b9c8d24b7e2020e264f960d2b032fec57637df863d6f47d0742efda5373` |
| TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.52.exe` | 90.052.475 byte | `0edb6b3c402c6b95089930a9d54ed585c5c9aa489c19e924d794e4f956a4cf3c` |

## Status paket

Build release bukan bukti pemasangan produksi atau UAT pengguna. Publikasi GitHub
tidak mengubah perangkat maupun server secara otomatis.
