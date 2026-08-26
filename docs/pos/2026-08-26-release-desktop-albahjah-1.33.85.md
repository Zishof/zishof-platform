# Rilis Al-Bahjah POS Desktop 1.33.85 (build 143)

Tanggal rilis: 26 Agustus 2026

## Masalah

Saat kasir membuka Pesanan, melihat detail, lalu memilih **Muat ke Keranjang**,
tanggal transaksi lama milik draft ikut dipulihkan. Akibatnya pembayaran atau
penahanan ulang dapat tersimpan memakai tanggal draft sebelumnya.

## Perbaikan

- Draft lama tetap menjadi sumber identitas, member, dan rincian barang, tetapi
  bukan lagi sumber waktu transaksi.
- **Muat ke Keranjang** mengisi tanggal/jam transaksi dengan waktu tindakan
  pemuatan.
- Pembayaran memakai waktu yang ditampilkan setelah draft dimuat.
- **Tahan** ulang mengambil waktu tindakan penahanan terbaru sebelum payload
  dikirim, sehingga pemuatan dan penahanan berikutnya tidak mewarisi waktu lama.
- Perubahan hanya pada client Flutter; backend SVN tidak diubah.

## UAT

- [x] Helper waktu menerima waktu pemuatan terbaru.
- [x] Penahanan ulang menerima waktu tindakan yang lebih baru.
- [x] Normalisasi duplikat rincian draft tetap lulus.
- [x] Analyzer empat file implementasi/tes: **No issues found**.
- [x] Seluruh suite aplikasi: **359/359 lulus**.
- [x] `git diff --check`: lulus.

## Build dan publikasi

- Varian: `albahjah`.
- Platform: Windows Desktop saja (`-SkipAndroid`).
- Versi: `1.33.85+143`.
- Skrip: `tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah`.
- Flutter Windows release dan kompilasi installer Inno Setup: **berhasil**.
- Product version installer: `1.33.85`.
- Commit implementasi: `02145c0`.
- Authenticode: `NotSigned` karena pipeline lokal belum mempunyai sertifikat.

## Artefak

| Berkas | Ukuran | SHA-256 |
|---|---:|---|
| `Al-Bahjah-POS-Setup-1.33.85.exe` | 46.163.518 byte | `8716EA80B78190CA75A49474372AA120B94251CB7FF4B4F00C6B67B585AA2F28` |

Manifest `.sha256.txt` hasil build telah dibandingkan dengan perhitungan ulang
dan cocok. Publikasi memakai tag `v1.33.85-build143` pada repository
`Zishof/zishof-platform`.
