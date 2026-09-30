# v1.34.53 build 216 - rebuild Windows Al-Bahjah dan TokoQu An Nahl

Rilis ini menaikkan versi aplikasi dari `1.34.52+215` menjadi `1.34.53+216`
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

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.53/` dan
tidak disimpan di Git.

| Varian | Installer | Ukuran | SHA-256 |
| --- | --- | ---: | --- |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.53.exe` | 89.914.315 byte | `e76d1c6a3f4b37e0956d1a8366a5ad0b34df2f986f89fb38dbb7d83d444f1aa5` |
| TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.53.exe` | 90.062.280 byte | `7a5b8bc3334fa9e93485ff05642a5397c3e7acae48e69b439cadf51879a79f82` |

## Status paket

Build release bukan bukti pemasangan produksi atau UAT pengguna. Publikasi GitHub
tidak mengubah perangkat maupun server secara otomatis.
