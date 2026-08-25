# Build Desktop POS Al-Bahjah dan eBisnis — 26 Agustus 2026

## Ruang lingkup

- Build ulang POS Desktop varian `albahjah` dan `ebisnis` dari kode terkini.
- Seluruh perubahan aktif pada repository disertakan dalam commit Git sesuai permintaan pengguna.
- Build Android dan publikasi GitHub Release tidak dijalankan pada pekerjaan ini.

## Perintah build

```powershell
& "C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\tool\build_semua_varian.ps1" -SkipAndroid -Hanya "albahjah,ebisnis"
```

## Hasil verifikasi

Build selesai tanpa kegagalan dan menghasilkan installer versi `1.33.82` berikut:

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.33.82.exe` | 46.163.432 byte | `B499A9D0323D8A8E8B1A62E64173B887D69E9354C7163B3BFA937D87C3902655` |
| eBisnis | `eBisnis-Setup-1.33.82.exe` | 46.105.993 byte | `54861C690F4526BBDD6949F61CFB4578153FB20A022D04000ADBF0A03ADBC23C` |

Lokasi keluaran:

```text
C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\release-artifacts\semua-varian\1.33.82\
```

## Kontrol kualitas

- `git diff --check`: lulus, tidak ditemukan whitespace error.
- Installer kedua varian ditemukan dan checksum SHA-256 berhasil dihitung.
- Repository ini bukan working copy SVN pada mesin ini; sinkronisasi kode dilakukan melalui Git `main`.
