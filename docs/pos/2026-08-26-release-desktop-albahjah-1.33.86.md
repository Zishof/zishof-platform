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
- [ ] Build Windows Desktop varian Al-Bahjah.

## Build dan publikasi

- Varian: `albahjah`.
- Platform: Windows Desktop saja (`-SkipAndroid`).
- Versi: `1.33.86+144`.
- Artefak, checksum, commit, tag, dan hasil publikasi GitHub dicatat setelah
  build selesai.
