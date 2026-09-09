# Hasil UAT Preflight Saldo POS v1.34.33

Tanggal pengujian: 10 September 2026

Build: `1.34.33+196`

Varian: eBisnis, Al-Bahjah, dan TokoQu Al-Bahjah An Nahl

## Sasaran pengujian

Memastikan pembayaran saldo/voucher yang tidak mencukupi dihentikan sebelum
transaksi atau outbox dibuat, tanpa mengurangi kemampuan local-first untuk
pembayaran tunai/manual yang aman.

## Skenario acuan

| Data | Nilai |
|---|---:|
| Saldo terbaru server | Rp3.100 |
| Nilai pembayaran saldo | Rp149.500 |
| Kekurangan | Rp146.400 |
| Hasil yang diharapkan | Transaksi belum dibuat; keranjang tetap utuh |

## Hasil

| Pemeriksaan | Hasil |
|---|---|
| Saldo sama dengan nominal | LULUS — pembayaran boleh dilanjutkan |
| Saldo Rp3.100 untuk pembayaran Rp149.500 | LULUS — diblokir sebelum transaksi |
| Split tunai+saldo | LULUS — hanya porsi saldo yang dibandingkan |
| Nilai saldo/nominal tidak valid | LULUS — ditolak |
| Urutan preflight terhadap kode transaksi, API bayar, dan outbox | LULUS — preflight paling awal |
| Pembayaran tunai/manual aman | LULUS — jalur local-first tetap aktif |
| Penolakan saldo lama | LULUS — tidak diulang otomatis |
| Snapshot metode pembayaran offline | LULUS — tetap dapat dipilih sesuai konteks |

Seluruh 20 skenario regresi saldo, metode pembayaran, outbox, dan refresh
metode lulus. Analisis statis pada berkas yang berubah juga lulus tanpa temuan.

Seluruh rangkaian regresi aplikasi juga dijalankan ulang dan **850/850
pengujian lulus**. Uji kanal auto-update dijalankan secara terpisah untuk
eBisnis, Al-Bahjah, dan Nahl; ketiganya mengarah ke prefiks rilis masing-masing
dan tidak saling bercampur.

## Hasil build Windows Desktop

| Varian | Artefak | SHA-256 | Hasil |
|---|---|---|---|
| eBisnis | `eBisnis-Setup-1.34.33.exe` | `62ee6afee3ee119df32d4c806402e270878b121c607bd5e1b23ebbe476b13b5c` | LULUS |
| Al-Bahjah | `Al-Bahjah-POS-Setup-1.34.33.exe` | `b9d2122ef6a6efd237c1220c2fbf5f2fd9899f64a0591ab75017fed2949285e9` | LULUS |
| Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.33.exe` | `209e603bd66d3568820bc7329323b716ef6cedc31db4fe4d99c6c1065684567a` | LULUS |

Versi produk pada ketiga installer terbaca `1.34.33` dan identitas produk
masing-masing sesuai varian. Nilai hash dihitung ulang dan sama dengan berkas
sidecar. Installer UAT Windows belum ditandatangani secara digital; verifikasi
integritas dilakukan menggunakan SHA-256 yang dipublikasikan bersama installer.

## Kontrol pencegahan

1. Kasir memilih member dan metode pembayaran.
2. Saldo pada layar bersifat informasi awal.
3. Ketika Bayar ditekan, aplikasi membaca ulang saldo pusat.
4. Bila saldo kurang atau server tidak tersedia, proses berhenti sebelum nomor
   transaksi, data lokal, atau outbox dibuat.
5. Bila cukup, server kembali memvalidasi secara atomik dan baru menerima
   transaksi.
6. Untuk tunai/manual aman, aplikasi tetap menyimpan lokal lebih dahulu dan
   menyinkronkan secara idempoten.

## Kesimpulan

**LULUS.** Kasus saldo lama tidak lagi menghasilkan transaksi pending baru.
Perubahan menjaga prinsip local-first dengan membedakan operasi yang aman
diantrikan dari otorisasi saldo yang wajib mendapatkan keputusan server.
