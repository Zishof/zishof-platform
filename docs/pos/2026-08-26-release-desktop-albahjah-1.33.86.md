# Rilis Al-Bahjah POS Desktop 1.33.86 (build 144)

Tanggal rilis: 26 Agustus 2026

## Masalah

Pada alur **Pesanan → Detail → Muat ke Keranjang**, member draft berhasil
dipulihkan tetapi pemuatan metode pembayaran langsung difilter memakai jenis
member tersebut. Akibatnya metode aktif yang dibutuhkan kasir, termasuk
**Kasbon Divisi**, tidak muncul pada pemilih pembayaran.

## Perbaikan

- Member awal dari draft tetap terpilih dan tetap dikirim pada payload
  pembayaran.
- Draft yang dimuat dari Pesanan mengambil semua metode pembayaran aktif saat
  panel dibuka dan setiap kali pemilih pembayaran dibuka kembali.
- Bila kasir mengganti member secara manual, penyaringan normal berdasarkan
  jenis member kembali berlaku.
- Perubahan hanya pada client Flutter; backend SVN tidak diubah.

## UAT

- [x] Jalur Pesanan menandai member awal agar memakai semua metode aktif.
- [x] Penanda diteruskan melalui Kasir Desktop dan Keranjang Mobile.
- [x] Picker menyegarkan daftar sebelum ditampilkan.
- [x] Penggantian member mengaktifkan kembali filter jenis member.
- [x] Tes regresi waktu transaksi draft tetap lulus.
- [x] Analyzer empat file implementasi/tes: **No issues found**.
- [x] Seluruh suite aplikasi: **361/361 lulus**.
- [x] `git diff --check`: lulus.
- [x] Build Windows Desktop varian Al-Bahjah: berhasil.

## Build dan publikasi

- Varian: `albahjah`.
- Platform: Windows Desktop saja (`-SkipAndroid`).
- Versi: `1.33.86+144`.
- Skrip: `tool/build_semua_varian.ps1 -SkipAndroid -Hanya albahjah`.
- Flutter Windows release dan kompilasi installer Inno Setup: **berhasil**.
- Product version installer: `1.33.86`.
- Commit implementasi: `0490288`.
- Authenticode: `NotSigned` karena pipeline lokal belum mempunyai sertifikat.

## Artefak

| Berkas | Ukuran | SHA-256 |
|---|---:|---|
| `Al-Bahjah-POS-Setup-1.33.86.exe` | 46.163.270 byte | `CB2AAAE7A1FCFF1BB3304CEAD607BFA39242AA74ED23A58F7395E2F4E78E19A5` |

Manifest `.sha256.txt` hasil build telah dibandingkan dengan perhitungan ulang
dan cocok. Publikasi memakai tag `v1.33.86-build144` pada repository
`Zishof/zishof-platform`.
