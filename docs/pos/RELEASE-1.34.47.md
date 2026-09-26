# v1.34.47 build 210 - rebuild Al-Bahjah dan TokoQu An Nahl

Rilis ini menaikkan versi aplikasi dari `1.34.46+209` menjadi `1.34.47+210`
dan membangun ulang installer Windows untuk varian:

- Al-Bahjah POS
- TokoQu Al-Bahjah An Nahl

## Validasi build

Perintah build:

```powershell
powershell -ExecutionPolicy Bypass -File tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah,nahl -IzinkanUnsignedWindows
```

Hasil: lulus, 2 artefak berhasil dibuat.

Installer Windows berhasil dibuat dan diverifikasi sebagai `UNSIGNED/UAT` karena
sertifikat Authenticode produksi tidak tersedia di sesi ini.

## Artefak Windows

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.47/` dan
tidak disimpan di Git.

| Varian | Installer | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.47.exe` | 89.902.297 byte | `d0817a55b89ce2a79c751e3ae652709b79dc811bd2a83e9e3fcea2fe04675fa1` |
| TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.47.exe` | 90.049.096 byte | `260cec3c2032d31dcd15d98b740feaee742556261417739d34d32a71e3283260` |

## Status paket

Build release bukan bukti pemasangan produksi atau UAT pengguna. Publikasi GitHub
tidak mengubah perangkat maupun server secara otomatis.
