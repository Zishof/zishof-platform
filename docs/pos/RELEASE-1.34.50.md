# v1.34.50 build 213 - rebuild Al-Bahjah dan TokoQu An Nahl

Rilis ini menaikkan versi aplikasi dari `1.34.49+212` menjadi `1.34.50+213`
dan membangun ulang paket Android serta installer Windows untuk varian:

- Al-Bahjah POS
- TokoQu Al-Bahjah An Nahl

## Validasi build

Perintah build:

```powershell
$env:ANDROID_SDK_ROOT="$env:LOCALAPPDATA\Android\Sdk"; $env:ANDROID_HOME=$env:ANDROID_SDK_ROOT; powershell -ExecutionPolicy Bypass -File tool\build_semua_varian.ps1 -Hanya albahjah,nahl -IzinkanUnsignedWindows -IzinkanDebugSigning
```

Hasil: lulus, 4 artefak berhasil dibuat.

APK Android berhasil dibuat dan diverifikasi sebagai `DEBUG/UAT` karena
sertifikat signing produksi Android tidak tersedia di sesi ini. Installer
Windows berhasil dibuat dan diverifikasi sebagai `UNSIGNED/UAT` karena
sertifikat Authenticode produksi tidak tersedia di sesi ini.

## Artefak

Artefak berada di `apps/ebisnis/release-artifacts/semua-varian/1.34.50/` dan
tidak disimpan di Git.

| Platform | Varian | Artefak | Ukuran | SHA-256 |
| --- | --- | --- | ---: | --- |
| Windows | Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.50.exe` | 89.923.152 byte | `32ffb7fd3061b2af468f461f29bc597a26078099d529143819b1ef64f2fed0ba` |
| Android | Al-Bahjah | `app-albahjah-release.apk` | 196.509.273 byte | `2a9f7116b5df2b98b6a20ab5ad61ddcd21f897c8b7878397d369468508811996` |
| Android | TokoQu Al-Bahjah An Nahl | `app-nahl-release.apk` | 196.514.300 byte | `a7d144658e15be93fe3f299e1f9c4df1bd8d65b3ed5a53910ac9aea9da4727c1` |
| Windows | TokoQu Al-Bahjah An Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.50.exe` | 90.062.474 byte | `2c0c3f3a3735f0563a6ae4119cb069c6e45d74cdbaf1b24ee674da3d508eb8cd` |

## Status paket

Build release bukan bukti pemasangan produksi atau UAT pengguna. Publikasi GitHub
tidak mengubah perangkat maupun server secara otomatis.
