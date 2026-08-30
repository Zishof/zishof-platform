# Rilis Desktop POS 1.34.12 — eBisnis, Al-Bahjah, dan TokoQu An-Nahl

Tanggal: 30 Agustus 2026  
Versi aplikasi: `1.34.12+174`  
Varian: `ebisnis`, `albahjah`, `nahl`  
Tag GitHub: `v1.34.12`  
Commit sumber aplikasi: `c571455`  
Prasyarat SO Harian: backend AIS SVN `r78609`

## Ringkasan perubahan

- Seluruh jalur CRUD yang dapat diantrikan wajib mengikuti kontrak local-first:
  simpan lokal dahulu, catat audit/outbox, lalu kirim ulang otomatis ke server.
- Kasir menawarkan sinkron produk dan tambah produk cepat bila barcode/nama belum
  ditemukan. Produk disimpan lokal lebih dahulu dan tidak hilang saat server
  sedang bermasalah.
- Pilihan metode pembayaran dapat disinkronkan ulang dari panel pembayaran agar
  aturan terbaru member tidak tertahan cache lama.
- Modul SO Harian menampilkan produk terjual per tanggal, jumlah terjual/retur,
  stok, serta alur unduh dan unggah Excel. Perbaikan pemetaan tipe native query
  berada pada backend AIS SVN `r78609`.
- Perbaikan stok opname, pembatalan oleh supervisor, audit CRUD, foto local-first,
  pencarian barcode, dan cetak label dari rilis-rilis sebelumnya tetap termasuk
  dalam build terpadu ini.

## Verifikasi sebelum rilis

- `flutter analyze` pada layar Kasir dan Keranjang: tidak ada masalah.
- Suite penuh: `572` tes lulus.
- Tes terarah Kasir, pencarian barcode, SO Harian, upload gambar local-first,
  urutan Keranjang, dan release guard: `15` tes lulus.
- `git diff --check` lulus.
- Tiga varian dikompilasi ulang dari commit dan nomor versi yang sama.
- Ketiga installer terbentuk oleh Inno Setup dan diverifikasi sebagai installer
  Windows internal/UAT. Artefak belum ditandatangani Authenticode.

## Artefak Desktop Windows

| Varian | Installer | Ukuran | SHA-256 |
|---|---|---:|---|
| eBisnis | `eBisnis-Setup-1.34.12.exe` | 85.844.774 byte | `C1F447A73690467709F5864099ABC6784FEF9FBC9230BFB5B9534E058CBDD81B` |
| Al-Bahjah POS | `Al-Bahjah-POS-Setup-1.34.12.exe` | 85.870.464 byte | `CA7D0AA20374C2A4A1C54E7F515E4C81BC5EC28FCDCC98FFDDFF0603624D3B1A` |
| TokoQu Al-Bahjah An-Nahl | `TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.12.exe` | 86.048.522 byte | `94FAA5673ED0E6F854095944F32422CCF6A6BDFFB8382942BA0D2C4849918F66` |

Lokasi artefak lokal:

`apps/ebisnis/release-artifacts/semua-varian/1.34.12/`

## UAT pemasangan

1. Tutup aplikasi lama tanpa menghapus database lokal, transaksi pending, outbox,
   cache, atau foto lokal.
2. Pasang installer sesuai varian dan pastikan versi kiri bawah `1.34.12`.
3. Pilih toko aktif, lalu tekan **Sinkronkan** satu kali.
4. Nahl: buka **Stok Opname > SO Harian**, pilih tanggal, dan pastikan daftar
   produk terjual serta fungsi Excel tampil setelah backend r78609 aktif.
5. Al-Bahjah: scan satu barcode produk. Jika master belum tersedia, gunakan
   tambah produk cepat; pastikan data tersimpan di perangkat dan antrean sinkron.
6. Periksa **Sistem > Riwayat Sinkronisasi**. Jangan menginput ulang data yang
   berstatus menunggu kirim.

## Rollback

- Bila aplikasi tidak dapat dibuka atau alur kasir terganggu, pasang kembali
  installer `v1.34.11`/versi stabil sebelumnya tanpa menghapus database lokal.
- Bila hanya SO Harian yang gagal, pertahankan data lokal dan periksa deployment
  backend r78609; jangan menghapus antrean atau mengulang input.
- Hentikan rollout bila checksum installer tidak cocok dengan tabel di atas.

