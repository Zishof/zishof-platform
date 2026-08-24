# POS Desktop 1.33.81 — Al-Bahjah dan eBisnis

Tanggal build: 24 Agustus 2026  
Versi aplikasi: `1.33.81+139`

## Ruang lingkup

Release ini memuat installer Windows Desktop untuk dua varian berikut:

- Al-Bahjah POS
- eBisnis POS

Masing-masing varian dibangun terpisah memakai konfigurasi branding, nama
aplikasi, executable, server bawaan, context path, dan lokasi data lokal milik
varian tersebut. Artefak satu varian tidak digunakan ulang untuk varian lain.

## Proses build

Build dilakukan dengan skrip resmi repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\build_semua_varian.ps1 `
  -SkipAndroid `
  -Hanya 'albahjah,ebisnis'
```

Hasil build menyatakan kedua varian berhasil dan installer Inno Setup selesai
dibuat tanpa error.

## Artefak dan integritas

| Artefak | Ukuran | SHA-256 |
|---|---:|---|
| `Al-Bahjah-POS-Setup-1.33.81.exe` | 46.134.708 byte | `4888b7713c1462c354b9bca5a4ccb287289493131bfe277ade2f44efd570c31c` |
| `eBisnis-Setup-1.33.81.exe` | 46.080.765 byte | `0fcdb90d6e547e839ee166bde3ff6d5cf4c243be941a264deef8814e95cf8ca0` |

Checksum kedua installer telah dibandingkan dengan file `.sha256.txt` hasil
build dan keduanya cocok.

## Verifikasi

- Branch `main` bersih dan sinkron dengan `origin/main` sebelum perubahan
  metadata versi.
- Build Windows release Flutter berhasil untuk varian eBisnis dan Al-Bahjah.
- Packaging installer Inno Setup berhasil untuk kedua varian.
- Nama executable internal Al-Bahjah terverifikasi sebagai
  `ebisnis_albahjah.exe`; eBisnis memakai `ebisnis.exe`.
- Tidak ada artefak Android yang dibangun atau dipublikasikan pada release ini.

